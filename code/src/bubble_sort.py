def sorter(arr):
    """Sort a list in ascending order using bubble sort.

    Attempts to use the built-in list sort method first. If the input does not
    support .sort() (e.g. a tuple or other sequence), falls back to a manual
    bubble sort implementation that repeatedly swaps adjacent elements.

    Args:
        arr: A list (or list-like sequence) of comparable elements to sort.

    Returns:
        The sorted sequence in ascending order.
    """
    print("codeflash stdout: Sorting list")
    try:
        arr.sort()
    except AttributeError:
        for i in range(len(arr)):
            for j in range(len(arr) - 1):
                if arr[j] > arr[j + 1]:
                    temp = arr[j]
                    arr[j] = arr[j + 1]
                    arr[j + 1] = temp
    print(f"result: {arr}")
    return arr
