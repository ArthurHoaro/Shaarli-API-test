#!/bin/sh
#
#  Copyright (c) 2015 Marcus Rohrmoser http://mro.name/me. All rights reserved.
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
cd "$(dirname "$0")"
. ./assert.sh

[ "$USERNAME" != "" ] || assert_fail 1 "How strange, USERNAME is unset."
[ "$PASSWORD" != "" ] || assert_fail 2 "How strange, PASSWORD is unset."
[ "$BASE_URL" != "" ] || assert_fail 3 "How strange, BASE_URL is unset."

echo "###################################################"
echo "## Non-logged-in Atom feed before adding a link (should have only the initial public default entry):"
curl --silent --show-error --output curl.tmp.atom "$BASE_URL/?do=atom"
xmllint --encode utf8 --format curl.tmp.atom
entries=$(xmllint --xpath 'count(/*/*[local-name()="entry"])' curl.tmp.atom)
[ $entries -eq 1 ] || assert_fail 4 "Atom feed expected 1 = $entries"

echo "####################################################"
echo "## Step 1: fetch token to login and add a new link: "
rm curl.tmp.*
# http://unix.stackexchange.com/a/157219
LOCATION=$(curl --get --url "$BASE_URL" \
  --data-urlencode "post=https://en.wikipedia.org/wiki/Gutenberg_Bible" \
  --data-urlencode "title=Movable type invented." \
  --data-urlencode "source=Source Text" \
  --cookie curl.cook --cookie-jar curl.cook \
  --location --output curl.tmp.html \
  --trace-ascii curl.tmp.trace --dump-header curl.tmp.head \
  --write-out '%{url_effective}' 2>/dev/null)
xsltproc --html --output curl.tmp.xml response.xslt curl.tmp.html 2>/dev/null || assert_fail 5 "Failed to fetch TOKEN"
cat curl.tmp.xml

errmsg=$(xmllint --xpath 'string(/shaarli/error/@message)' curl.tmp.xml)
[ "$errmsg" = "" ] || assert_fail 107 "error: '$errmsg'"
TOKEN=$(xmllint --xpath 'string(/shaarli/form[@name="loginform"]/input[@name="token"]/@value)' curl.tmp.xml)
# string(..) http://stackoverflow.com/a/18390404

# the precise length doesn't matter, it just has to be significantly larger than ''
[ $(printf "%s" $TOKEN | wc -c) -eq 40 ] || assert_fail 6 "expected TOKEN of 40 characters, but found $TOKEN of $(printf "%s" $TOKEN | wc -c)"

echo "######################################################"
echo "## Step 2: follow the redirect and get the post form: "
rm curl.tmp.*
LOCATION=$(curl --url "$LOCATION" \
  --data-urlencode "login=$USERNAME" \
  --data-urlencode "password=$PASSWORD" \
  --data-urlencode "token=$TOKEN" \
  --cookie curl.cook --cookie-jar curl.cook \
  --location --output curl.tmp.html \
  --trace-ascii curl.tmp.trace --dump-header curl.tmp.head \
  --write-out '%{url_effective}' 2>/dev/null)
xsltproc --html --output curl.tmp.xml response.xslt curl.tmp.html 2>/dev/null || assert_fail 7 "Failure"
cat curl.tmp.xml
errmsg=$(xmllint --xpath 'string(/shaarli/error/@message)' curl.tmp.xml)
[ "$errmsg" = "" ] || assert_fail 108 "error: '$errmsg'"
[ $(xmllint --xpath 'count(/shaarli/is_logged_in[@value="true"])' curl.tmp.xml) -eq 1 ] || assert_fail 8 "expected to be logged in now"

# turn response.xml form input field data into curl commandline parameters or post file
ruby response2post.rb < curl.tmp.xml > curl.post

echo "######################################################"
echo "## Step 3: finally post the link: "
rm curl.tmp.*
curl --url "$LOCATION" \
  --data "@curl.post" \
  --data-urlencode "lf_linkdate=15460801_120001" \
  --data-urlencode "lf_source=$0" \
  --data-urlencode "lf_description=First movable-type bible printed." \
  --data-urlencode "lf_tags=t1 t2" \
  --data-urlencode "save_edit=Save" \
  --cookie curl.cook --cookie-jar curl.cook \
  --location --output curl.tmp.html \
  --trace-ascii curl.tmp.trace --dump-header curl.tmp.head \
  2>/dev/null
xsltproc --html --output curl.tmp.xml response.xslt curl.tmp.html 2>/dev/null
cat curl.tmp.xml

#####################################################
[ $(xmllint --xpath 'count(/shaarli/is_logged_in[@value="true"])' curl.tmp.xml) -eq 1 ] || assert_fail 9 "expected to be still logged in"
# TODO: watch out for error messages like e.g. ip bans or the like.

# check post-condition - there must be more entries now:
# there is an ugly caching issue - so I use a different atom URL down here:
echo "###################################################"
echo "## Logged-in Atom feed after adding a link (should have all three, the added and the initial default public and private entries):"
curl --silent --show-error --cookie curl.cook --cookie-jar curl.cook --output curl.tmp.atom "$BASE_URL/?do=atom&nb=all"
xmllint --encode utf8 --format curl.tmp.atom
entries=$(xmllint --xpath 'count(/*/*[local-name()="entry"])' curl.tmp.atom)
[ $entries -eq 3 ] || assert_fail 10 "Atom feed expected 3 = $entries"
