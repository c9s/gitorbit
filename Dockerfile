FROM golang:1.10-alpine3.7 AS src
RUN apk add --no-cache git
WORKDIR /go/src
RUN go get -u github.com/kardianos/govendor
COPY cmd /go/src/cmd
COPY vendor /go/src/vendor
RUN govendor sync -v
RUN go install ./cmd/authorized-keys

FROM alpine:3.7
RUN apk update
RUN apk add openssh git shadow
RUN apk add curl
RUN apk add bash
RUN apk add mongodb

# Generate host keys
RUN ssh-keygen -A
WORKDIR /home/git

# --create-home             create the user's home directory
# --user-group              create a group with the same name as the user
# RUN adduser -D -s /usr/bin/git-shell git \
RUN useradd --user-group --create-home --shell /bin/bash git \
 && usermod -p '*' git \
 && mkdir -p /home/git/keys /home/git/.ssh \
 && chown -R git:git /home/git \
 && chmod 700 /home/git/keys /home/git/.ssh \
 && find /home/git/.ssh /home/git/keys -type f -exec chmod 600 {} \;

ARG REPOS_DIR=/repositories
RUN mkdir -p $REPOS_DIR \
 && chmod 700 $REPOS_DIR \
 && git init --bare $REPOS_DIR/test.git \
 && chown -R git:git $REPOS_DIR \
 && find $REPOS_DIR -type f -exec chmod 600 {} \;

# This is a login shell for SSH accounts to provide restricted Git access.
# It permits execution only of server-side Git commands implementing the
# pull/push functionality, plus custom commands present in a subdirectory
# named git-shell-commands in the user’s home directory.
# More info: https://git-scm.com/docs/git-shell
COPY git-shell-commands /home/git/git-shell-commands

# COPY git-authorized-keys.sh /authorized-keys
ARG CACHE
COPY --from=src /go/bin/authorized-keys /authorized-keys

COPY git-command.sh /git-command

RUN mkdir -p /var/log/git && chown -R git:git /var/log/git
ARG CONFIG=config/docker.json

RUN mkdir -p /etc/gitorbit
COPY $CONFIG /etc/gitorbit/authorized_keys.json

# sshd_config file is edited for enable access key and disable access password
# COPY sshd_config /etc/ssh/sshd_config
COPY start.sh /start.sh

# %f token passes the fingerprint SHA256:wi76P4RkpL9gWJx/p1Jr35r0Ri0/50NFPI4cVbT/4vc
RUN sed -i -e "/AuthorizedKeysCommand none/c\AuthorizedKeysCommand /authorized-keys -config /etc/gitorbit/authorized_keys.json %f" /etc/ssh/sshd_config
RUN sed -i -e "/AuthorizedKeysCommandUser /c\AuthorizedKeysCommandUser git" /etc/ssh/sshd_config

# Disable password authentication
RUN sed -i -e "/#PasswordAuthentication/c\PasswordAuthentication no" /etc/ssh/sshd_config

# Use public key authentication
RUN sed -i -e "/#PubkeyAuthentication/c\PubkeyAuthentication yes" /etc/ssh/sshd_config

# Enable password-locked account
# see also https://unix.stackexchange.com/questions/193066/how-to-unlock-account-for-public-key-ssh-authorization-but-not-for-password-aut
# RUN sed -i -e "/#UsePAM/c\UsePAM yes" /etc/ssh/sshd_config

RUN sed -i -e "/#LogLevel /c\LogLevel DEBUG" /etc/ssh/sshd_config

EXPOSE 22
CMD ["sh", "/start.sh"]
