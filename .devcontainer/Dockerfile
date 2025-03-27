FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    vim \
    zsh \
    gcc \
    gcc-multilib \
    libssl-dev \
    pkg-config \
    git \
    build-essential \
    lldb \
    gdb \
    linux-tools-common \
    strace \
    lsof \
    tcpdump \
    iproute2 \
    iputils-ping \
    fonts-powerline \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 安装 Rust
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup component add rust-src rustfmt clippy

# 安装 Golang
ARG GO_VERSION=1.22.1
RUN wget -O go.tgz https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go.tgz \
    && rm go.tgz

# 配置 Go 环境
ENV GOPATH=/go
ENV PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

# 安装一些常用的 Go 工具
RUN go install golang.org/x/tools/gopls@latest \
    && go install github.com/go-delve/delve/cmd/dlv@latest

# 安装 Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended [2](https://ohmyz.sh/)

# 安装常用 Zsh 插件
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# 配置 Zsh
RUN sed -i 's/plugins=(git)/plugins=(git golang rust docker zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc \
    && echo 'export GOPATH=/go' >> ~/.zshrc \
    && echo 'export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin' >> ~/.zshrc \
    && echo 'ZSH_THEME="agnoster"' >> ~/.zshrc

# 可选：设置默认 shell 为 zsh
SHELL ["/bin/zsh", "-c"]

WORKDIR /workspace