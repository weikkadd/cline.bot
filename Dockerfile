# syntax=docker/dockerfile:1

FROM node:24-alpine

WORKDIR /app

# Copy only the manifests first so dependency layers stay cached.
# cline.bot has no runtime dependencies, so there is no install step.
COPY --chown=node:node package.json ./
COPY --chown=node:node server.js ./

# Deplexo runs containers as an unprivileged user with a read-only root
# filesystem. The app never writes to disk, so no extra permissions are needed.
USER node

ENV NODE_ENV=production \
    PORT=3000

EXPOSE 3000

# Exec form so the process receives SIGTERM directly and can shut down cleanly.
CMD ["node", "server.js"]
