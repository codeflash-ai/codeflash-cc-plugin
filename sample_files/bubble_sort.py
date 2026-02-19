def sorter(arr):
    """Sort a list in-place using the bubble sort algorithm.

    Iterates through the list repeatedly, swapping adjacent elements that are
    out of order until the entire list is sorted in ascending order.

    Args:
        arr: A list of comparable elements to sort.

    Returns:
        The same list, sorted in ascending order.
    """
    print("codeflash stdout: Sorting list")
    for i in range(len(arr)):
        for j in range(len(arr) - 1):
            if arr[j] > arr[j + 1]:
                temp = arr[j]
                arr[j] = arr[j + 1]
                arr[j + 1] = temp
    print(f"result: {arr}")
    return arr
