def sorter(arr):
    print("codeflash stdout: Sorting list")
    if isinstance(arr, list):
        arr.sort()
    else:
        n = len(arr)
        a = arr
        for i in range(n):
            swapped = False
            # After i passes the last i elements are already in place
            for j in range(0, n - i - 1):
                aj = a[j]
                aj1 = a[j + 1]
                if aj > aj1:
                    a[j] = aj1
                    a[j + 1] = aj
                    swapped = True
            if not swapped:
                break
    print(f"result: {arr}")
    return arr
