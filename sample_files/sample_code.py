import numpy as np

def tridiagonal_solve(a: np.ndarray, b: np.ndarray, c: np.ndarray, d: np.ndarray) -> np.ndarray:
    n = len(b)

    # Create working copies to avoid modifying input
    c_prime = np.zeros(n - 1, dtype=np.float64)
    d_prime = np.zeros(n, dtype=np.float64)
    x = np.zeros(n, dtype=np.float64)

    # Forward sweep - sequential dependency: c_prime[i] depends on c_prime[i-1]
    c_prime[0] = c[0] / b[0]
    d_prime[0] = d[0] / b[0]

    for i in range(1, n - 1):
        denom = b[i] - a[i - 1] * c_prime[i - 1]
        c_prime[i] = c[i] / denom
        d_prime[i] = (d[i] - a[i - 1] * d_prime[i - 1]) / denom

    # Last row of forward sweep
    denom = b[n - 1] - a[n - 2] * c_prime[n - 2]
    d_prime[n - 1] = (d[n - 1] - a[n - 2] * d_prime[n - 2]) / denom

    # Back substitution - sequential dependency: x[i] depends on x[i+1]
    x[n - 1] = d_prime[n - 1]
    for i in range(n - 2, -1, -1):
        x[i] = d_prime[i] - c_prime[i] * x[i + 1]

    return x