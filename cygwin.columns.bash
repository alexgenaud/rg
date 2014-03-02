############################################################
#
# all this function does is return the $COLUMNS env var from
# an interactive shell. The terminal width is not available
# in an non-interactive shell. This seems to work in Cygwin,
# but does not work in most Linux. However eval $( resize )
# seems to work in Linux but not Cygwin. Hack yes. Profit!
# 
############################################################
echo $COLUMNS
