import numpy as np

def leapfrog_integration(
    positions: np.ndarray,
    velocities: np.ndarray,
    masses: np.ndarray,
    dt: float,
    n_steps: int,
    softening: float = 0.01
) -> tuple[np.ndarray, np.ndarray]:
    """Simulate N-body gravitational dynamics using the leapfrog integration scheme.

    Uses a kick-drift-kick variant of the symplectic leapfrog integrator to evolve
    particle positions and velocities under mutual gravitational attraction, with
    gravitational softening to prevent singularities at close encounters.

    Args:
        positions: Initial positions of shape (n_particles, 3).
        velocities: Initial velocities of shape (n_particles, 3).
        masses: Particle masses of shape (n_particles,).
        dt: Integration timestep.
        n_steps: Number of integration steps to perform.
        softening: Gravitational softening length to avoid divergence at zero separation.

    Returns:
        A tuple of (final_positions, final_velocities), each of shape (n_particles, 3).
    """
    n_particles = len(masses)
    pos = positions.copy()
    vel = velocities.copy()
    acc = np.zeros_like(pos)

    G = 1.0

    for step in range(n_steps):
        acc.fill(0.0)

        for i in range(n_particles):
            for j in range(i + 1, n_particles):
                dx = pos[j, 0] - pos[i, 0]
                dy = pos[j, 1] - pos[i, 1]
                dz = pos[j, 2] - pos[i, 2]

                dist_sq = dx * dx + dy * dy + dz * dz + softening * softening
                dist = np.sqrt(dist_sq)
                dist_cubed = dist_sq * dist

                force_over_dist = G / dist_cubed

                acc[i, 0] += masses[j] * force_over_dist * dx
                acc[i, 1] += masses[j] * force_over_dist * dy
                acc[i, 2] += masses[j] * force_over_dist * dz

                acc[j, 0] -= masses[i] * force_over_dist * dx
                acc[j, 1] -= masses[i] * force_over_dist * dy
                acc[j, 2] -= masses[i] * force_over_dist * dz

        for i in range(n_particles):
            vel[i, 0] += 0.5 * dt * acc[i, 0]
            vel[i, 1] += 0.5 * dt * acc[i, 1]
            vel[i, 2] += 0.5 * dt * acc[i, 2]

        for i in range(n_particles):
            pos[i, 0] += dt * vel[i, 0]
            pos[i, 1] += dt * vel[i, 1]
            pos[i, 2] += dt * vel[i, 2]

        for i in range(n_particles):
            vel[i, 0] += 0.5 * dt * acc[i, 0]
            vel[i, 1] += 0.5 * dt * acc[i, 1]
            vel[i, 2] += 0.5 * dt * acc[i, 2]

    return pos, vel
