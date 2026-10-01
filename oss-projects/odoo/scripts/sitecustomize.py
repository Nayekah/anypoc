import collections
import collections.abc

for _name in (
    "Mapping",
    "MutableMapping",
    "Sequence",
    "MutableSequence",
    "Set",
    "MutableSet",
    "Iterable",
    "Iterator",
    "Callable",
):
    if not hasattr(collections, _name):
        setattr(collections, _name, getattr(collections.abc, _name))
