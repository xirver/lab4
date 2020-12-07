# Copyright 2020 Lin Wang

# This code is part of the Advanced Computer Networks (2020) course at Vrije 
# Universiteit Amsterdam.

# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# Navigate to the home directory
cd ~

# Source
BMV2_COMMIT="9982947acb075a18697a77e21e27e805e4167c05"  # October 25, 2020
PI_COMMIT="e16d99a18d3ad22d6f68b283e45d1441bc9b1bbd"    # October 25, 2020
P4C_COMMIT="159d29677df1eb39527864e38725e74d68c18714"   # October 25, 2020
PROTOBUF_COMMIT="v3.13.0"	# October 25, 2020
GRPC_COMMIT="v1.33.1"			# October 25, 2020

# Get the number of cores to speed up the compilation process
NUM_CORES=`grep -c ^processor /proc/cpuinfo`

# Protobuf 
git clone https://github.com/google/protobuf.git
cd protobuf
git checkout ${PROTOBUF_COMMIT}
export CFLAGS="-Os"
export CXXFLAGS="-Os"
export LDFLAGS="-Wl,-s"
./autogen.sh
./configure --prefix=/usr
make -j${NUM_CORES}
sudo make install
sudo ldconfig
unset CFLAGS CXXFLAGS LDFLAGS
# Force install python module
cd python
python setup.py build
sudo pip install .
cd ../..

# gRPC
git clone https://github.com/grpc/grpc.git
cd grpc
git checkout ${GRPC_COMMIT}
git submodule update --init --recursive

# Fix a bug when compiling with cmake. 
# Need to build dependency packages explicitly due to cmake version <3.13.
# Fix by Vinod Nigade
GRPC_DEP_PACKAGES="abseil-cpp cares/cares re2"
for package in ${GRPC_DEP_PACKAGES}; do
	pushd .
	cd third_party/${package}
	mkdir build
	cd build
	cmake -DBUILD_SHARED_LIBS=ON ../
	sudo make install -j${NUM_CORES}
	popd
done
mkdir -p cmake/build
pushd cmake/build
cmake -DgRPC_RE2_PROVIDER=package \
	-DgRPC_ABSL_PROVIDER=package \
	-DgRPC_INSTALL=ON \
	-DgRPC_BUILD_TESTS=OFF \
	-DgRPC_PROTOBUF_PROVIDER=package \
	-DgRPC_ZLIB_PROVIDER=package \
	-DgRPC_CARES_PROVIDER=package \
	-DgRPC_SSL_PROVIDER=package \
	-DCMAKE_BUILD_TYPE=Release \
	../.. 
make -j${NUM_CORES}
sudo make install
sudo ldconfig
popd
cd ..
# Install gRPC Python Package
sudo pip install grpcio


# BMv2 deps (needed by PI)
git clone https://github.com/p4lang/behavioral-model.git
cd behavioral-model
git checkout ${BMV2_COMMIT}
# From bmv2's install_deps.sh, we can skip apt-get install.
# Nanomsg is required by p4runtime, p4runtime is needed by BMv2...
tmpdir=`mktemp -d -p .`
cd ${tmpdir}
bash ../travis/install-thrift.sh
bash ../travis/install-nanomsg.sh
sudo ldconfig
bash ../travis/install-nnpy.sh
cd ..
sudo rm -rf $tmpdir
cd ..

# PI/P4Runtime
git clone https://github.com/p4lang/PI.git
cd PI
git checkout ${PI_COMMIT}
git submodule update --init --recursive
./autogen.sh
./configure --with-proto
make -j${NUM_CORES}
sudo make install
sudo ldconfig
cd ..

# Bmv2
cd behavioral-model
./autogen.sh
./configure --enable-debugger --with-pi
make -j${NUM_CORES}
sudo make install
sudo ldconfig
# Simple_switch_grpc target
cd targets/simple_switch_grpc
./autogen.sh
./configure --with-thrift
make -j${NUM_CORES}
sudo make install
sudo ldconfig
cd ../../..


# P4C
git clone https://github.com/p4lang/p4c
cd p4c
git checkout ${P4C_COMMIT}
git submodule update --init --recursive
mkdir -p build
cd build
cmake ..
make -j${NUM_CORES}
sudo make install
sudo ldconfig
cd ../..

# Back to the project working directory 
cd /vagrant/

# Install VLC
sudo apt install vlc
