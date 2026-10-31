FROM mcr.microsoft.com/powershell:lts-ubuntu-22.04
RUN pwsh -NoProfile -Command "Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module Pode -RequiredVersion 2.12.0 -Scope AllUsers; Install-Module Pode.Web -RequiredVersion 0.8.3 -Scope AllUsers"
WORKDIR /app
COPY PowerBGP ./PowerBGP
COPY PowerBGP.Pode ./PowerBGP.Pode
# Use host networking to reach lab devices:
#   podman run --rm --network host powerbgp
# TCP-MD5 sessions started in a rootful container without extra capabilities (tested with Podman).
# If your runtime restricts it, add --cap-add NET_ADMIN.
EXPOSE 8085
CMD ["pwsh", "-NoProfile", "-File", "/app/PowerBGP.Pode/server.ps1", "-Address", "0.0.0.0"]
