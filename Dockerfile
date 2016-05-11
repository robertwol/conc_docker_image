FROM concourse/concourse-ci
# https://github.com/concourse/concourse/blob/master/ci/dockerfiles/concourse-ci/Dockerfile

RUN apt-get update && \
    apt-get -y install curl

# cf cli
ADD https://cli.run.pivotal.io/stable?release=debian64&version=6.14.0&source=github-rel /tmp/cf-cli.deb
RUN dpkg -i /tmp/cf-cli.deb

# jq
RUN apt-get -y install jq

# yaml2json (and npm)
#RUN apt-get -y install npm && \
#    npm install -g yaml2json
RUN apt-get -y install golang bzr && \
    mkdir /root/golang && \
    echo "export GOPATH=/root/golang" >> ~/.profile && \
    echo 'export PATH="$PATH:$GOPATH/bin"' >> ~/.profile && \
    go get github.com/bronze1man/yaml2json

# AWS CLI
# RUN python --version
RUN apt-get -y install python && \
    curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip" && \
    unzip awscli-bundle.zip && \
    ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
#RUN aws help ec2
