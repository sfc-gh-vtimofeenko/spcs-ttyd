# Sample Dockerfile to add ttyd to a base image

FROM debian:sid
# If using other base Linux distribution -- make sure that ttyd is available in the repositories
RUN apt update && apt-get install -y ttyd
# Sample parameters for running locally/debugging
# EXPOSE 40000
# ENTRYPOINT [ "ttyd", "--port=40000", "--writable", "bash"]
