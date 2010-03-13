#!/bin/sh
#/ Usage: pgem-install <name>...
#/ Install package <name>
set -e

. pgem-sh-setup

name="$1"
vers="${2:->=0}"

# Usage: pgem_ln <source> <dest>
# Attempt to hard link <dest> to <source> but fall back to cp(1) if
# you're crossing file systems or the ln fails otherwise.
pgem_ln () {
    if ln -f "$1" "$2"; then
        log install "$2 [ln]"
    else
        log install "$2 [cp]"
        cp "$1" "$2"
    fi
}

# Recursive file hierarchy copy routine. Attempts to hardlink files
# and falls back to normal copies.
pgem_install_dir () {
    local src="$1" dest="$2" manifest="$3"
    mkdir -p "$dest"
    for file in "$1"/*
    do
        if test -f "$file"
        then
            # link dest to source
            pgem_ln "$file" "$dest/$(basename $file)"
            echo "$dest/$(basename $file)" >> "$manifest"
        elif test -d "$file"
        then
            # recurse into directories
            pgem_install_dir "$file" "$dest/$(basename $file)" "$manifest"
        else
            warn "unknown file type: $file"
            return 1
        fi
    done
    return 0
}

# Fetch the gem into the cache.
gemfile=$(pgem-fetch $name $vers) ||
exit 1
gemname=$(basename ${gemfile%.gem})
gemvers=${gemname##*-}

# Install all dependencies
pgem-deps "$gemfile" |
xargs -n 2 pgem install

# Unpack the gem into the packages area if its not already there
test -d "$PGEMPACKS/$gemname" || {
    log unpack "$gemfile"
    mkdir -p "$PGEMPACKS"
    cd "$PGEMPACKS"
    gem unpack "$gemfile" >/dev/null
}

# Get the manifest file going.
dbdir="$PGEMDB/$name"
manifest="$dbdir/$gemvers"

# Check if the package already has an installed version
test -e "$dbdir/active" && {
    curvers=$(readlink $dbdir/active)
    if pgem-version-test "$curvers" "$vers"
    then
        log uptodate "$name $curvers is installed"
        exit 0
    else
        log conflict "$name $curvers installed but you want $gemvers"
        unlink "$dbdir/active"
    fi
}

log install $name $vers

mkdir -p "$dbdir"
echo "# $(date)" > "$manifest"
ln -sf "$gemvers" "$dbdir/installing"

# Go into the unpackaged package dir to make installing a bit easier.
cd "$PGEMPACKS/$gemname"

# Build extension libraries if they exist
exts="$(pgem-build "$(pwd)")" || abort "extension failed to build"

test -n "$exts" && {
    mkdir -p "$PGEMLIB"
    echo "$exts" |
    while read dl
    do
        # make install sitearchdir=#{manager.dir}/lib
        prefix=$(
            grep '^target_prefix.=' "$(dirname $dl)/Makefile" |
            sed 's/^target_prefix *= *//'
        )
        dest="${PGEMLIB}${prefix}/$(basename $dl)"
        pgem_ln "$dl" "$dest"
        echo "$dest" >> "$manifest"
    done
}

# Install all library files.
test -d lib && {
    mkdir -p "$PGEMLIB"
    pgem_install_dir lib "$PGEMLIB" "$manifest"
}

# Install executables
test -d bin && {
    mkdir -p "$PGEMBIN"
    for file in bin/*
    do
        dest="$PGEMBIN/$(basename $file)"
        log install "$dest [+x]"
        sed "s@^#!.*ruby.*@#!$(pgem_rubybin)@" \
            < "$file" \
            > "$dest"
        chmod 0755 "$dest"
        echo "$dest" >> "$manifest"
    done
}

# Install manpages
test -d man && {
    for file in man/*
    do
        if test -f "$file" && expr "$file" : '.*\.[0-9]' >/dev/null
        then
            section=${file##*\.}
            dest="$PGEMMAN/man$section/$(basename $file)"
            mkdir -p "$PGEMMAN/man$section"
            pgem_ln "$file" "$dest"
            echo "$dest" >> "$manifest"
        fi
    done
}

# Mark this package as active
unlink "$dbdir/installing"
ln -sf "$gemvers" "$dbdir/active"
