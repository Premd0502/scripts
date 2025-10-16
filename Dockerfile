# Use Ubuntu 22.10 base image
FROM ubuntu:22.10

# Avoid interactive apt prompts
ENV DEBIAN_FRONTEND=noninteractive

# Switch to old-releases since 22.10 is EOL
RUN sed -i 's|http://archive.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' /etc/apt/sources.list && \
    sed -i 's|http://security.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' /etc/apt/sources.list

# Update, upgrade, and install dependencies (with Python 3.10)
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        perl \
        perl-base \
        perl-modules \
        cpanminus \
        build-essential \
        libxml-libxml-perl \
        libencode-perl \
        libjson-xs-perl \
        libjson-perl \
        libwww-perl \
        libfile-path-perl \
        libhttp-message-perl \
        libdatetime-perl \
        vim curl git \
        python3.10 python3.10-distutils python3.10-venv && \
    rm -rf /var/lib/apt/lists/*

# Install remaining Perl modules via cpanm
RUN cpanm \
    DBI \
    Net::FTP::File \
    JSON \
    Scalar::Util \
    LWP::UserAgent

# Create a working directory
WORKDIR /app

# Create a directory (for data access inside container)
RUN mkdir -p /data && chmod 755 /data

# Default command
CMD ["/bin/bash"]

