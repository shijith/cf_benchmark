#!/bin/bash

out=`pwd`/$1

echo $out

nprocs=`cat /proc/cpuinfo | awk '/^processor/{print $3}' | wc -l`

sudo apt-get install -y build-essential bc

git submodule update --init --recursive

# Build openssl
cd openssl
if [ ! -f ./apps/openssl ]; then
	./config no-shared && make -j
fi
cd ..

# Build compression
cd comp_bench
if [ ! -f ./bench ]; then
	make
fi
cd ..

# Build lua bench
cd lua_bench
if [ ! -f ./bench ]; then
	make
fi
cd ..


openssl_aead () {
	res=`./openssl/apps/openssl speed -seconds 10 -bytes 16384 -multi $2 -evp $1 | tail -1  | rev | cut -f 1 -d ' ' | rev | sed 's/k//' `
	gib=`echo "scale=3; $res * 1000 / 1024 / 1024 / 1024" | bc`
	echo $gib GiB/s
}

openssl_sign () {
	res=`./openssl/apps/openssl speed -seconds 10 -multi $2 $1 | tail -1  | tr -s ' ' | rev | cut -f 2 -d ' ' | rev`
	echo $res ops/s
}

openssl_verify () {
	res=`./openssl/apps/openssl speed -seconds 10 -multi $2 $1 | tail -1  | tr -s ' ' | rev | cut -f 1 -d ' ' | rev` 
	echo $res ops/s
}

comp () {
	res=`./comp_bench/bench -q $1 -c $2 $3 ./comp_bench/index.html | tail -1 | cut -f 2 -d','`
	echo $res MiB/s
}

echo benchmark,1 core,$nprocs cores | tee $out

echo "brotli performance" | tee -a $out
for q in {4..11}; do
	echo brotli -$q,$( comp $q 1 -b),$( comp $q $nprocs -b ) | tee -a $out
done

echo "gzip performance (cloudflare zlib)" | tee -a $out
for q in {4..9}; do
	echo gzip -$q,$( comp $q 1 ),$( comp $q $nprocs ) | tee -a $out
done

echo openssl pki performance | tee -a $out
for sig in ecdsap256 rsa2048 rsa3072; do
	echo $sig Sign,$( openssl_sign $sig 1), $( openssl_sign $sig $nprocs) | tee -a $out
	echo $sig Verify,$( openssl_verify $sig 1), $( openssl_verify $sig $nprocs) | tee -a $out
done

for kx in ecdhp256 ecdhx25519; do
	echo $kx Key-Exchange,$( openssl_verify $kx 1), $( openssl_verify $kx $nprocs) | tee -a $out
done

echo openssl aead performance | tee -a $out
for aead in aes-128-gcm aes-256-gcm chacha20-poly1305; do
	echo $aead,$( openssl_aead $aead 1 ), $( openssl_aead $aead $nprocs ) | tee -a $out
done

