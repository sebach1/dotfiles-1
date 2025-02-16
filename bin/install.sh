#!/bin/bash
set -e
set -o pipefail

# install.sh
#	This script installs my basic setup for a ubuntu pc

# Choose a user account to use for this installation
get_user() {
	if [ -z "${TARGET_USER-}" ]; then
		mapfile -t options < <(find /home/* -maxdepth 0 -printf "%f\\n" -type d)
		# if there is only one option just use that user
		if [ "${#options[@]}" -eq "1" ]; then
			readonly TARGET_USER="${options[0]}"
			echo "Using user account: ${TARGET_USER}"
			return
		fi

		# iterate through the user options and print them
		PS3='command -v user account should be used? '

		select opt in "${options[@]}"; do
			readonly TARGET_USER=$opt
			break
		done
		fi
	}

check_is_sudo() {
	if [ "$EUID" -ne 0 ]; then
		echo "Please run as root."
		exit
	fi
}


setup_sources_min() {
	apt update
	apt install -y \
		apt-transport-https \
		curl \
		--no-install-recommends


	# turn off translations, speed up apt update
	mkdir -p /etc/apt/apt.conf.d
	echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99translations
}

# sets up apt sources
# assumes you are going to use ubuntu
setup_sources() {
	setup_sources_min;

	cat <<-EOF > /etc/apt/sources.list
	deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main universe restricted multiverse
	EOF
}

base() {
	apt update
	apt -y upgrade

	apt install -y \
		automake \
		bash-completion \
		clipit \
		curl \
		fonts-firacode \
		git \
		grep \
		gzip \
		jq \
		less \
		lua5.2 \
		make \
		silversearcher-ag \
		sudo \
		tar \
		tree \
		tzdata \
		unzip \
		vim-gtk3 \
		zip \
		--no-install-recommends

	if ! [ -x "$(command -v bat)" ]; then
		wget -O /home/$TARGET_USER/Downloads/bat.deb https://github.com/sharkdp/bat/releases/download/v0.15.4/bat_0.15.4_amd64.deb
		dpkg -i /home/$TARGET_USER/Downloads/bat.deb
	fi

	# fd
	if ! [ -x "$(command -v fd)" ]; then
		wget -O /home/$TARGET_USER/Downloads/fd.deb https://github.com/sharkdp/fd/releases/download/v8.1.1/fd-musl_8.1.1_amd64.deb
		dpkg -i /home/$TARGET_USER/Downloads/fd.deb
	fi

	# vscode
	if ! [ -x "$(command -v code)" ]; then
		snap install --classic code
	fi

	install_scripts

	apt update
	apt -y upgrade

	setup_sudo

	apt autoremove
	apt autoclean
	apt clean

}

# setup sudo for a user
setup_sudo() {
	# add user to sudoers
	adduser "$TARGET_USER" sudo

	# setup downloads folder as tmpfs
	# that way things are removed on reboot
	mkdir -p "/home/$TARGET_USER/Downloads"
	echo -e "\\n# tmpfs for downloads\\ntmpfs\\t/home/${TARGET_USER}/Downloads\\ttmpfs\\tnodev,nosuid,size=5G\\t0\\t0" >> /etc/fstab

	# add go path to secure path
	{ \
		echo -e "Defaults	secure_path=\"/usr/local/go/bin:/home/${TARGET_USER}/.go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/share/bcc/tools:/home/${TARGET_USER}/.cargo/bin\""; \
		echo -e "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL"; \
	} >> /etc/sudoers
	# create docker group
	sudo groupadd docker
	sudo gpasswd -a "$TARGET_USER" docker
}

# install rust
install_rust() {
	curl https://sh.rustup.rs -sSf | sh
}

# install/update golang from source
install_golang() {
	export GO_VERSION
	GO_VERSION=$(curl -sSL "https://golang.org/VERSION?m=text")
	export GO_SRC=/usr/local/go

	# if we are passing the version
	if [[ -n "$1" ]]; then
		GO_VERSION=$1
	fi

	# purge old src
	if [[ -d "$GO_SRC" ]]; then
		sudo rm -rf "$GO_SRC"
		sudo rm -rf "$GOPATH"
	fi

	GO_VERSION=${GO_VERSION#go}

	# subshell
	(
	kernel=$(uname -s | tr '[:upper:]' '[:lower:]')
	curl -sSL "https://storage.googleapis.com/golang/go${GO_VERSION}.${kernel}-amd64.tar.gz" | sudo tar -v -C /usr/local -xz
	local user="$USER"
	# rebuild stdlib for faster builds
	sudo chown -R "${user}" /usr/local/go/pkg
	CGO_ENABLED=0 go install -a -installsuffix cgo std
	)

	# get commandline tools
	set -x
	set +e
	go get golang.org/x/lint/golint
	go get golang.org/x/tools/cmd/cover
	go get golang.org/x/tools/cmd/gopls
	go get golang.org/x/tools/cmd/goimports
	go get golang.org/x/tools/cmd/gorename
	go get golang.org/x/tools/cmd/guru

	go get github.com/genuinetools/amicontained
	go get github.com/genuinetools/apk-file
	go get github.com/genuinetools/pepper
	go get github.com/genuinetools/certok
	go get github.com/genuinetools/reg
	go get github.com/genuinetools/udict
	go get github.com/genuinetools/weather

	go get github.com/jessfraz/gmailfilters
	go get github.com/jessfraz/junk/sembump
	go get github.com/jessfraz/tdash

	go get github.com/axw/gocov/gocov
	go get honnef.co/go/tools/cmd/staticcheck
	go get github.com/golangci/golangci-lint

	# Tools for vimgo.
	go get github.com/jstemmer/gotags
	go get github.com/nsf/gocode
	go get github.com/rogpeppe/godef

	# Autocompletion for go cli
	go get -u github.com/posener/complete/gocomplete

	# symlink weather binary for motd
	sudo ln -snf "${GOPATH}/bin/weather" /usr/local/bin/weather
}


# install custom scripts/binaries
install_scripts() {
	# install speedtest
	curl -sSL https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py  > /usr/local/bin/speedtest
	chmod +x /usr/local/bin/speedtest

	# install fuzzy finder (fzf)
	if [[ ! -d "/home/${TARGET_USER}/.fzf" ]]; then
		git clone --depth 1 https://github.com/junegunn/fzf.git /home/$TARGET_USER/.fzf
		/home/$TARGET_USER/.fzf/install
	fi

	# install z lua
	if [[ ! -d "/home/${TARGET_USER}/.z.lua" ]]; then
		git clone https://github.com/skywind3000/z.lua /home/$TARGET_USER/.z.lua
	fi


	local scripts=( have light )

	for script in "${scripts[@]}"; do
		curl -sSL "https://misc.j3ss.co/binaries/$script" > "/usr/local/bin/${script}"
		chmod +x "/usr/local/bin/${script}"
	done
}

# install stuff for i3 window manager
install_wmapps() {
	apt update || true
	apt install -y \
		alsa-utils \
		feh \
		i3 \
		i3lock \
		i3status \
		scrot \
		suckless-tools \
		rxvt-unicode-256color \
		usbmuxd \
		xclip \
		xcompmgr \
		--no-install-recommends

	# update clickpad settings
	# get correct sound cards on boot
	curl -sSL https://raw.githubusercontent.com/jessfraz/dotfiles/master/etc/modprobe.d/intel.conf > /etc/modprobe.d/intel.conf

	# pretty fonts
	curl -sSL https://raw.githubusercontent.com/jessfraz/dotfiles/master/etc/fonts/local.conf > /etc/fonts/local.conf

	dpkg-reconfigure fontconfig
}

get_dotfiles() {
	# create subshell
	(
	cd "/home/$TARGET_USER"

	if [[ ! -d "/home/${TARGET_USER}/dotfiles" ]]; then
		# install dotfiles from repo
		git clone git@github.com:schattian/dotfiles.git "/home/${TARGET_USER}/dotfiles"
	fi

	cd "/home/${TARGET_USER}/dotfiles"

	# set the correct origin
	git remote set-url origin git@github.com:schattian/dotfiles.git

	# installs all the things
	make

	# enable dbus for the user session
	# systemctl --user enable dbus.socket

	sudo systemctl enable "i3lock@${TARGET_USER}"
		sudo systemctl enable suspend-sedation.service

	cd "/home/$TARGET_USER"
	mkdir -p /home/$TARGET_USER/Pictures/Screenshots
	)

	install_vim;
}

install_vim() {
	# create subshell
	(
	cd "/home/$TARGET_USER"

	# install .vim files
	(
	cd "/home/${TARGET_USER}/.vim"
	make install
	)

	# update alternatives to vim
	sudo update-alternatives --install /usr/bin/vi vi "$(command -v vim)" 60
	sudo update-alternatives --config vi
	sudo update-alternatives --install /usr/bin/editor editor "$(command -v vim)" 60
	sudo update-alternatives --config editor
	)
}

install_tools() {
	echo "Installing golang..."
	echo
	install_golang;

	echo
	echo "Installing rust..."
	echo
	install_rust;

	echo
	echo "Installing scripts..."
	echo
	sudo install.sh scripts;
}

usage() {
	echo -e "install.sh\\n\\tThis script installs my basic setup for a ubuntu distro\\n"
	echo "Usage:"
	echo "  base                                - setup sources & install base pkgs"
	echo "  projects                            - setup projects folder"
	echo "  wm                                  - install window manager/desktop pkgs"
	echo "  dotfiles                            - get dotfiles"
	echo "  vim                                 - install vim specific dotfiles"
	echo "  golang                              - install golang and packages"
	echo "  rust                                - install rust"
	echo "  scripts                             - install scripts"
	echo "  tools                               - install golang, rust, and scripts"
}

main() {
	local cmd=$1
	get_user

	if [[ -z "$cmd" ]]; then
		usage
		exit 1
	fi

	if [[ $cmd == "base" ]]; then
		check_is_sudo
		# setup /etc/apt/sources.list
		setup_sources

		base
	elif [[ $cmd == "projects" ]]; then
		clone_projects
	elif [[ $cmd == "wm" ]]; then
		check_is_sudo
		install_wmapps
	elif [[ $cmd == "dotfiles" ]]; then
		get_dotfiles
	elif [[ $cmd == "vim" ]]; then
		install_vim
	elif [[ $cmd == "rust" ]]; then
		install_rust
	elif [[ $cmd == "golang" ]]; then
		install_golang "$2"
	elif [[ $cmd == "scripts" ]]; then
		install_scripts
	elif [[ $cmd == "tools" ]]; then
		install_tools
	else
		usage
	fi
}

main "$@"
