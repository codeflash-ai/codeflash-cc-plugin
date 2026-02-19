def sorter(arr):
    """Sort a sequence in-place and return it."""
    print("codeflash stdout: Sorting list")
    # Fast path for built-in lists: use the highly optimized C implementation.
    if isinstance(arr, list):
        arr.sort()
        print(f"result: {arr}")
        return arr

    # If the object exposes an in-place sort method, prefer it to preserve semantics.
    sort_method = getattr(arr, "sort", None)
    if callable(sort_method):
        sort_method()
        print(f"result: {arr}")
        return arr

    # Fallback: create a sorted list and assign elements back into the original object.
    # This preserves in-place mutation of the provided object (and will raise the same
    # assignment-related exceptions for immutable sequences such as tuples).
    n = len(arr)
    sorted_arr = sorted(arr)
    for i in range(n):
        arr[i] = sorted_arr[i]

    print(f"result: {arr}")
    return arr
