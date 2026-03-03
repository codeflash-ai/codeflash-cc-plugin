def sorter(arr):
    print("codeflash stdout: Sorting list")
    if isinstance(arr, list):
        arr.sort()
    else:
        n = len(arr)
        # Precompute the inner range to avoid recreating it every iteration
        # Use a shrinking inner range and an early-exit flag to reduce work
        if n > 1:
            for i in range(n):
                swapped = False
                # Reduce the inner loop bound each pass since the tail becomes sorted
                upper = n - 1 - i
                for j in range(upper):
                    if arr[j] > arr[j + 1]:
                        arr[j], arr[j + 1] = arr[j + 1], arr[j]
                        swapped = True
                if not swapped:
                    break
    print(f"result: {arr}")
    return arr
