#!/usr/bin/env python3
"""
Evidence Checker - Validate POC evidence and attempt reproduction

This module reads the collected evidence to understand expected signals, then
attempts to reproduce the POC to confirm validity. Reproduction results are the
source of truth; evidence alone is not trusted.
"""

import asyncio
import shutil
import subprocess
from pathlib import Path

from caw import Agent, ToolGroup

from anypoc.types import EvidenceCheckOutcome, EvidenceCheckStatus
from anypoc.utils import logger

LOG_PREFIX = "[Evidence Checker]"
CheckResult = EvidenceCheckStatus


async def _send_with_heartbeat(session, prompt: str, title: str, interval_seconds: int = 30):
    """Run a blocking agent turn while emitting periodic heartbeat logs."""
    turn_task = asyncio.create_task(asyncio.to_thread(session.send, prompt))
    elapsed = 0

    while True:
        try:
            return await asyncio.wait_for(asyncio.shield(turn_task), timeout=interval_seconds)
        except asyncio.TimeoutError:
            elapsed += interval_seconds
            logger.info(f"{LOG_PREFIX} {title} still running ({elapsed}s elapsed)")


def _best_effort_make_executable(path: Path) -> None:
    """Attempt to add execute bits, but tolerate filesystems that reject chmod."""
    try:
        path.chmod(0o755)
    except PermissionError:
        logger.warn(f"{LOG_PREFIX} Could not chmod {path}; continuing with explicit bash execution")
    except OSError as exc:
        logger.warn(f"{LOG_PREFIX} Could not chmod {path}: {exc}; continuing with explicit bash execution")


def _copytree_without_metadata(src: Path, dst: Path) -> None:
    """Copy a directory tree without preserving chmod/stat metadata."""
    for path in sorted(src.rglob("*")):
        relative = path.relative_to(src)
        target = dst / relative
        if path.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue

        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)


def _save_prompts_to_file(path: Path, prompts: list[tuple[str, str]], title: str) -> None:
    """Save a list of (step_name, prompt) tuples to a markdown file."""
    content_parts = [f"# {title}\n"]
    for idx, (step_name, prompt) in enumerate(prompts, start=1):
        content_parts.append(f"## Step {idx}: {step_name}\n\n{prompt}\n")
    path.write_text("\n---\n\n".join(content_parts))


async def check_evidence(
    poc_dir: Path,
    evidence_dir: Path,
    reproduce_dir: Path,
    playground_dir: Path,
    filtered_bug_report: str,
    trajs_dir: Path,
    custom_prompt: str | None = None,
) -> tuple[CheckResult, str]:
    """
    Check evidence and attempt reproduction of the POC.

    Args:
        poc_dir: Directory containing POC artifacts
        evidence_dir: Directory containing collected evidence
        reproduce_dir: Directory for reproduction attempts
        playground_dir: Directory containing the codebase
        filtered_bug_report: The validated bug report content
        trajs_dir: Directory for saving trajectory files
        custom_prompt: Optional project-specific prompt to append

    Returns:
        Tuple of (CheckResult, explanation) where:
        - CheckResult: The validation status
        - explanation: Detailed explanation of the result
    """
    reproduce_dir.mkdir(parents=True, exist_ok=True)

    # Check if agent declared PoC impossible
    impossible_file = poc_dir / "IMPOSSIBLE.md"
    if impossible_file.exists():
        explanation = impossible_file.read_text()
        logger.info(f"{LOG_PREFIX} PoC marked impossible")
        return CheckResult.IMPOSSIBLE, explanation

    auto_result = _check_evidence_automatically(poc_dir, reproduce_dir)
    if auto_result is not None:
        logger.info(f"{LOG_PREFIX} Automatic reproduction complete")
        return auto_result

    agent = _build_agent(playground_dir, poc_dir, evidence_dir, reproduce_dir, trajs_dir)

    # Build all prompts upfront
    evidence_prompt = _build_evidence_analysis_prompt(filtered_bug_report, poc_dir, evidence_dir)
    reproduce_prompt = _build_reproduction_prompt(poc_dir, reproduce_dir, custom_prompt)
    status_prompt = _build_status_determination_prompt(reproduce_dir)

    # Save all prompts to trajs directory
    _save_prompts_to_file(
        trajs_dir / "evidence_checker_prompts.md",
        [
            ("Evidence Analysis", evidence_prompt),
            ("Reproduction", reproduce_prompt),
            ("Status Determination", status_prompt),
        ],
        "Evidence Checker Prompts",
    )

    logger.info(f"{LOG_PREFIX} Checking...")

    with agent.start_session(traj_path=trajs_dir / "evidence_checker.traj.json") as session:
        # Step 1: Analyze evidence
        logger.info(f"{LOG_PREFIX} Reviewing evidence context")
        await _send_with_heartbeat(session, evidence_prompt, "Evidence review")

        # Step 2: Attempt reproduction
        logger.info(f"{LOG_PREFIX} Reproducing")
        await _send_with_heartbeat(session, reproduce_prompt, "Reproduction")

        # Step 3: Determine final status
        logger.info(f"{LOG_PREFIX} Determining status")
        turn = await _send_with_heartbeat(session, status_prompt, "Status determination")
        status_response = turn.result

    # Save raw response
    check_result_path = reproduce_dir / "check_result.md"
    check_result_path.write_text(status_response)

    outcome = await EvidenceCheckOutcome.extract_from_text_async(status_response)
    result = outcome.status if outcome else _parse_check_result(status_response)
    explanation = outcome.conclusion or status_response if outcome else status_response
    logger.info(f"{LOG_PREFIX} Result: {result.value}")

    # Save parsed result as JSON if available
    if outcome:
        result_json_path = reproduce_dir / "check_result.json"
        outcome.to_json_file(result_json_path)

    return result, explanation


def _check_evidence_automatically(
    poc_dir: Path,
    reproduce_dir: Path,
) -> tuple[CheckResult, str] | None:
    """Use a deterministic local checker when the PoC already provides a runner.

    This avoids unnecessary model turns for straightforward replay-only PoCs such
    as file-based parser reproducers that ship a self-contained `run_poc.sh`.
    """
    run_script = poc_dir / "run_poc.sh"
    if not run_script.exists():
        return None

    replay_dir = reproduce_dir / "poc"
    replay_evidence_dir = reproduce_dir / "evidence"
    replay_evidence_dir.mkdir(parents=True, exist_ok=True)

    if replay_dir.exists():
        shutil.rmtree(replay_dir)
    replay_dir.mkdir(parents=True, exist_ok=True)
    _copytree_without_metadata(poc_dir, replay_dir)

    copied_run_script = replay_dir / "run_poc.sh"
    _best_effort_make_executable(copied_run_script)

    stdout_path = replay_evidence_dir / "auto_reproduction.stdout"
    stderr_path = replay_evidence_dir / "auto_reproduction.stderr"
    log_path = replay_evidence_dir / "auto_reproduction.log"
    status_path = replay_evidence_dir / "auto_reproduction_status.txt"

    result = subprocess.run(
        ["bash", str(copied_run_script)],
        cwd=replay_dir,
        capture_output=True,
        text=True,
        check=False,
    )

    stdout_path.write_text(result.stdout)
    stderr_path.write_text(result.stderr)
    log_path.write_text(
        f"$ bash {copied_run_script}\n"
        f"exit_status={result.returncode}\n"
        f"\n--- stdout ---\n{result.stdout}"
        f"\n--- stderr ---\n{result.stderr}"
    )
    status_path.write_text(str(result.returncode))

    generated_dir = replay_dir / "generated"
    generated_files = []
    if generated_dir.exists():
        generated_files = [str(path.relative_to(replay_dir)) for path in sorted(generated_dir.iterdir()) if path.is_file()]

    if result.returncode == 0:
        explanation = (
            "Automatic reproduction succeeded by replaying run_poc.sh from a clean copy of the PoC directory.\n\n"
            f"- Reproduction directory: {replay_dir}\n"
            f"- Evidence log: {log_path}\n"
            f"- Exit status: {result.returncode}\n"
        )
        if generated_files:
            explanation += "- Generated files:\n" + "\n".join(f"  - {name}" for name in generated_files)
        return CheckResult.PASSED, explanation

    explanation = (
        "Automatic reproduction failed when replaying run_poc.sh from a clean copy of the PoC directory.\n\n"
        f"- Reproduction directory: {replay_dir}\n"
        f"- Evidence log: {log_path}\n"
        f"- Exit status: {result.returncode}\n"
    )
    if generated_files:
        explanation += "- Generated files:\n" + "\n".join(f"  - {name}" for name in generated_files)
    return CheckResult.NOT_REPRODUCIBLE, explanation


def _build_agent(
    playground_dir: Path,
    poc_dir: Path,
    evidence_dir: Path,
    reproduce_dir: Path,
    trajs_dir: Path,
) -> Agent:
    playground = playground_dir.resolve()
    poc = poc_dir.resolve()
    evidence = evidence_dir.resolve()
    reproduce = reproduce_dir.resolve()

    instructions = f"""You are an expert security researcher tasked with validating POC evidence and reproduction.

You have access to:
- Repository snapshot: {playground}
- POC artifacts: {poc}
- Collected evidence: {evidence}
- Reproduction workspace: {reproduce}

Your job is to:
1. Read the collected evidence only to understand expected signals and claims
2. Independently attempt to reproduce the POC in the reproduction workspace
3. Base your final status on reproduction results, not on whether the provided evidence looks convincing
4. Evaluate whether the PoC represents a user-triggerable scenario — something a real user
   or attacker could trigger through normal interaction surfaces (file input, network request,
   API call, etc.), not just a potentially invalid internal function call or test harness

Be thorough and objective. A valid POC must be reproducible and clearly user-triggerable."""

    return Agent(
        name="Evidence Checker",
        description="Validates POC evidence and attempts reproduction.",
        system_prompt=instructions,
        tools=ToolGroup.NO_INTERACTION,
        data_dir=None,
    )


def _build_evidence_analysis_prompt(
    filtered_bug_report: str,
    poc_dir: Path,
    evidence_dir: Path,
) -> str:
    return f"""Read the provided evidence only to understand what was claimed and what signals to expect.

Do **not** decide validity based on the evidence alone — the only thing that matters is whether reproduction
succeeds. Treat the evidence as a hint about expected behavior, not as proof.

## Validated Bug Report:
{filtered_bug_report}

## Inputs to read:
- Evidence files: {evidence_dir}
- POC artifacts: {poc_dir}

Provide a concise summary of what the evidence claims should happen and what signals to look for during reproduction."""


def _build_reproduction_prompt(
    poc_dir: Path,
    reproduce_dir: Path,
    custom_prompt: str | None = None,
) -> str:
    # Build custom prompt section if provided
    custom_section = ""
    if custom_prompt:
        custom_section = f"""
## Project-Specific Instructions:
{custom_prompt}
"""

    return f"""Attempt to reproduce the POC independently. The provided evidence may be incomplete or even incorrect,
so rely on your own execution results.

Use the validated bug report context established in the previous step.

## POC Location: {poc_dir}

## Your Tasks:

1. Copy the POC to your reproduction workspace: {reproduce_dir}
2. Execute the POC following the same steps as the original
3. Collect new evidence of the reproduction attempt
4. Save reproduction evidence to: {reproduce_dir}/evidence/

## Important:
- Follow the exact same execution steps
- Record all outputs, logs, and any crashes
- Note any differences from the original evidence
- If the POC requires specific setup, document it
{custom_section}
Report whether the reproduction succeeded or failed."""


def _build_status_determination_prompt(reproduce_dir: Path) -> str:
    schema_description = EvidenceCheckOutcome.to_prompt_description()

    return f"""Based on your reproduction attempt, determine the final status. Trust your own run results over any
claimed evidence.

## Reproduction workspace: {reproduce_dir}

## Allowed statuses:
- PASSED: Reproduction succeeded and bug manifested
- FLAKY: Reproduction is inconsistent but signals suggest the bug is real
- NOT_REPRODUCIBLE: Reproduction failed and the PoC appears invalid
- INVALID_EVIDENCE: Reproduction failed and prior evidence looks incorrect/misleading
- IMPOSSIBLE: Fundamental blocker prevents reproduction (environment, missing hardware, etc.)

## User-Triggerability Check

In addition to reproduction, evaluate whether the PoC clearly represents something a
real user or attacker could trigger through normal interaction surfaces (file input,
network request, API call, etc.).

- A good PoC makes it obvious to a triaging developer that the bug is reachable from
  user-controlled input, without requiring them to trace code paths.
- If the PoC only calls internal functions in a way that simulates state that users cannot reach,
  reject the PoC as invalid or impossible.
- You should NOT reject all internal tests or PoCs with code modifications.
  Some such PoCs are genuinely useful if they clearly demonstrate a user-triggerable scenario that is hard to set up otherwise.

## Final Response Format:
Your final message MUST contain the full check result directly using the following structure:
{schema_description}"""


def _parse_check_result(response: str) -> EvidenceCheckStatus:
    """Fallback parser for check result when structured extraction fails."""
    response_upper = response.upper()

    if "PASSED" in response_upper:
        return EvidenceCheckStatus.PASSED
    if "FLAKY" in response_upper:
        return EvidenceCheckStatus.FLAKY
    if "INVALID_EVIDENCE" in response_upper or "INVALID EVIDENCE" in response_upper:
        return EvidenceCheckStatus.INVALID_EVIDENCE
    if "IMPOSSIBLE" in response_upper:
        return EvidenceCheckStatus.IMPOSSIBLE
    return EvidenceCheckStatus.NOT_REPRODUCIBLE
