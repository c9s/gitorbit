# GitServer

## Features

- MongoDB-based ssh public key authentication.
- Multiple ssh public key support for each user.
- Kubernetes deployment support.
- Support permission customization.

## Install

### Setup with Docker 

By default, the git-server image includes a config file:

```json
{
    "mongo": {
        "url": "mongodb://mongo:27017/git"
    },
    "logger": {
        "dir": "/var/log/git",
        "level": "debug",
        "maxAge": "720h",
        "suffixPattern": ".%Y%m%d",
        "linkName": "access_log"
    }
}
```

Which uses `mongodb://mongo:27017/git` as the connection string for the mongo client.

And so you will need to create a mongodb container instance with the name `mongo`, so that
the client can connect to your mongodb server.

First, you need to create a network for sharing the mongodb network connection:

```sh
docker network create docker
```

Start the mongodb server with the network that we just created:

```sh
docker run --name mongo \
    --restart=always \
    --publish 27018:27017 \
    --network docker \
    --detach mongo
```

Get your public key footprint and the key:

```sh
SSH_PUBKEY=$(cat ~/.ssh/id_rsa.pub)
SSH_PUBKEY_FINGERPRINT=$(ssh-keygen -lf ~/.ssh/id_rsa.pub | awk '{ print $2 }')
GIT_USER_EMAIL=$(git config user.email)
```

Insert the user in the mongodb:

```sh
mongo mongodb://localhost:27018/git --eval "
    db.users.insert({
        email: \"$GIT_USER_EMAIL\",
        keys: [{
                \"name\": \"dev\",
                \"fingerprint\": \"$SSH_PUBKEY_FINGERPRINT\",
                \"key\": \"$SSH_PUBKEY\"
            }]
    })"
```

Ensure that you can find the user by the fingerprint:

```sh
mongo mongodb://localhost:27018/git --eval "db.users.find({
    \"keys.fingerprint\": \"$SSH_PUBKEY_FINGERPRINT\" }).pretty()"
```

Build and Run the git server:

```sh
make stop build run
```

Add an entry in your .ssh/config:

```ssh
Host git-server
    HostName localhost
    User git
    Port 2022
    LogLevel INFO
    PreferredAuthentications publickey
    IdentityFile ~/.ssh/id_rsa
```

Now you can try git clone:

```sh
git clone git@git-server:test.git
```

### Kubernetes

Coming soon.

## License

MIT License

## Author

Yo-An Lin <yoanlin93@gmail.com>
