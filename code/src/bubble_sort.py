def sorter(arr):
    """Sort a list in ascending order using the bubble sort algorithm.

    Args:
        arr: A list of comparable elements to be sorted in-place.

    Returns:
        The sorted list in ascending order.
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
