# Build stage — compiles the React app
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Serve stage — nginx serving the static build output
FROM nginx:stable-alpine
COPY --from=build /app/build /usr/share/nginx/html
# If using Vite instead of CRA, change the line above to:
# COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
