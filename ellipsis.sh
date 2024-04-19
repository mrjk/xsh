#!/usr/bin/env bash
##############################################################################

pkg.link() {
    # Link xsh in the bin folder
    fs.link_file "$PKG_PATH/xsh" "$ELLIPSIS_HOME/.local/bin/xsh"
}

##############################################################################

pkg.unlink() {
    # Remove xsh link from the bin folder
    rm "$ELLIPSIS_HOME/xsh"
}

##############################################################################
