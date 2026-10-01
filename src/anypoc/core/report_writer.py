#!/usr/bin/env python3
"""
Report Writer - Generate concise bug report for developers

This module creates a submission-ready bug report from validated findings.
"""

import re
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
from pathlib import Path

from caw import Agent, ToolGroup

from anypoc.utils import logger

LOG_PREFIX = "[Report Writer]"


def _send_with_heartbeat(session, prompt: str, title: str, interval_seconds: int = 30):
    """Run a blocking agent turn while emitting periodic heartbeat logs."""
    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(session.send, prompt)
        elapsed = 0

        while True:
            try:
                return future.result(timeout=interval_seconds)
            except FutureTimeoutError:
                elapsed += interval_seconds
                logger.info(f"{LOG_PREFIX} {title} still running ({elapsed}s elapsed)")


def write_report(
    filtered_bug_report: str,
    poc_dir: Path,
    output_dir: Path,
    trajs_dir: Path,
    bug_report_format: str | None = None,
) -> Path:
    """
    Generate a concise bug report for submission to developers.

    Args:
        filtered_bug_report: The validated bug report content
        poc_dir: Directory containing POC artifacts
        output_dir: Output directory for the report
        trajs_dir: Directory for saving trajectory files
        bug_report_format: Optional project-specific report format template

    Returns:
        Path to the generated report file
    """
    report_path = output_dir / "report_to_submit.md"

    agent = _build_agent(poc_dir, trajs_dir)
    prompt = _build_report_prompt(filtered_bug_report, poc_dir, bug_report_format)

    # Save the prompt to trajs directory
    prompt_path = trajs_dir / "report_writer_prompt.md"
    prompt_path.write_text(f"# Report Writer Prompt\n\n{prompt}")

    logger.info(f"{LOG_PREFIX} Writing report...")

    report_content = ""
    try:
        with agent.start_session(traj_path=trajs_dir / "report_writer.traj.json") as session:
            turn = _send_with_heartbeat(session, prompt, "Report generation")
            report_content = turn.result
    except Exception as exc:
        logger.warn(f"{LOG_PREFIX} Model report generation failed, using fallback writer: {exc}")
        report_content = _build_fallback_report(filtered_bug_report, poc_dir)

    # Save the report
    if report_content:
        report_path.write_text(report_content)

    logger.info(f"{LOG_PREFIX} Done")
    return report_path


def _build_agent(poc_dir: Path, trajs_dir: Path) -> Agent:
    instructions = f"""You are writing a bug report for the project's security team.

Be concise and precise. The developers are experts - no need for excessive context or explanation.
POC files in {poc_dir} will be zipped and attached separately.
"""

    return Agent(
        name="Report Writer",
        description="Generates concise bug reports for developers.",
        system_prompt=instructions,
        tools=ToolGroup.NO_INTERACTION,
        data_dir=None,
    )


def _build_report_prompt(
    filtered_bug_report: str,
    poc_dir: Path,
    bug_report_format: str | None = None,
) -> str:
    # Build format section based on whether a custom format is provided
    if bug_report_format:
        format_section = f"""## Report Format:
Your response MUST be a markdown document following this exact format:

{bug_report_format}

Fill in each section based on the bug report and POC artifacts.
Output ONLY the filled-in report, no additional commentary."""
    else:
        format_section = """## Report Format:
Write a concise markdown report with:
- A clear title
- Files to submit section
- Vulnerable code location(s)
- Brief vulnerability analysis
- Impact description

Output ONLY the report content, no additional commentary."""

    return f"""Write a concise bug report for submission to the security team.

## Validated Bug Report:
{filtered_bug_report}

## POC Directory: {poc_dir}
Review the POC files and reference them in your report.

{format_section}

    Keep it short. No fluff."""


def _extract_title(filtered_bug_report: str) -> str:
    for line in filtered_bug_report.splitlines():
        stripped = line.strip()
        if stripped.startswith("# "):
            return stripped[2:].strip()
    return "AnyPoC reproduction report"


def _extract_section(filtered_bug_report: str, heading: str) -> str:
    pattern = re.compile(rf"^## {re.escape(heading)}\s*$", re.MULTILINE)
    match = pattern.search(filtered_bug_report)
    if not match:
        return ""
    start = match.end()
    next_match = re.search(r"^##\s+", filtered_bug_report[start:], re.MULTILINE)
    end = start + next_match.start() if next_match else len(filtered_bug_report)
    return filtered_bug_report[start:end].strip()


def _build_fallback_report(filtered_bug_report: str, poc_dir: Path) -> str:
    title = _extract_title(filtered_bug_report)
    poc_summary = _extract_section(filtered_bug_report, "Desired PoC") or "See attached PoC artifacts."
    analysis = _extract_section(filtered_bug_report, "Actual Behavior") or _extract_section(
        filtered_bug_report, "Affected Code"
    )
    impact = _extract_section(filtered_bug_report, "Impact") or "See attached PoC artifacts and reproduction logs."

    files = []
    for path in sorted(poc_dir.rglob("*")):
        if path.is_file():
            files.append(path.relative_to(poc_dir).as_posix())
    files_block = "\n".join(f"- `{name}`" for name in files) if files else "- No PoC files were captured."

    return (
        f"# {title}\n\n"
        "## Proof-of-Concept\n\n"
        f"{poc_summary}\n\n"
        "Attached files:\n"
        f"{files_block}\n\n"
        "## Vulnerable code analysis\n\n"
        f"{analysis or 'See the validated bug report and reproduction artifacts.'}\n\n"
        "## Impact\n\n"
        f"{impact}\n"
    )
