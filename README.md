# bake - A Simple Package Manager

**PRE PRE ALPHA: ANYTHING DESCRIBED HERE IS HOW THINGS SHOULD WORK IN THE FUTURE, NOT
WHATS ALREADY IMPLEMENTED. USE AT YOUR OWN RISK.**

## Prerequisites

Packages are build from source. At a minimum, a C/C++ compiler and buildtools are required.

On Debian/Ubuntu install:
```
sudo apt install build-essential
```

## Installation and update

Clone the repository and add it to your path:
```
git clone https://github.com/fweig/bake.git
echo "PATH+=:$PWD/bake" >> ~/.bashrc
```

To update, simply pull the `main` branch:
```
cd bake && git pull
```

## Usage

Create a new environment called `dev` with the latest gcc as the current compiler:
```
bake.sh bootstrap dev gcc
```
(**Warning**: This compiles gcc from scratch. Depending on your machine this could take a while.)

Then enter the new environment:
```
bake.sh enter dev
```

And install other packages:
```
bake.sh install cmake
```
