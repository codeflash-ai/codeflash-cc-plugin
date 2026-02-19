def sorter(arr):
    """Sort a sequence in place and return it."""
    print("codeflash stdout: Sorting list")
    # Prefer the built-in in-place sort where available (O(n log n)).
    # If no sort() method is present, compute a sorted sequence and
    # write it back element-wise to preserve in-place mutation semantics.
    sort_method = getattr(arr, "sort", None)
    if callable(sort_method):
        sort_method()
    else:
        sorted_seq = sorted(arr)
        for i in range(len(sorted_seq)):
            arr[i] = sorted_seq[i]
    print(f"result: {arr}")
    return arr
