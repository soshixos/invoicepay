# InvoicePay — static frontend served by nginx
# Build:  docker build -t invoicepay .
# Run:    docker run --rm -p 8080:80 invoicepay
# Open:   http://localhost:8080
#
# The image is fully self-contained: ethers.js is vendored under
# frontend/vendor/, so the demo works with no CDN access.
# The frontend talks to the Aevum Testnet public RPC by default; the
# deployed contract address lives in frontend/config.js.
FROM nginx:alpine

LABEL org.opencontainers.image.title="InvoicePay"
LABEL org.opencontainers.image.description="Stablecoin invoice payments on the QDay Aevum Testnet (tUSD8). Aevum Builder Challenge #1 — Invoice Payments track."
LABEL org.opencontainers.image.source="https://github.com/soshixos/qday-invoice-payments"

# nginx default config already serves /usr/share/nginx/html on port 80.
COPY frontend/ /usr/share/nginx/html/

# Cache-bust nothing: the app is a handful of static files.
EXPOSE 80

# nginx:alpine's default CMD runs nginx in the foreground.
