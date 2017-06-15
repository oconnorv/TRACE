#!/usr/bin/env bash

#RUN_TIME=(date +%Y-%m-%dT%I:%M:%S)
RUN_TIME="2017-06-12T14:30:01"

a-curl()
{
	URL="http://localhost:8080/fedora/objects?query=";
	C_DATE="cDate%3E%3D""$RUN_TIME";
	M_DATE="%20mDate%3E%3D""$RUN_TIME";
	PIDS="%20pid%7Eutk.ir*";
	ARGS="&pid=true&resultFormat=xml";
	REQUEST=$(curl -s "$URL""$C_DATE""$M_DATE""$PIDS""$ARGS")
	# xmlstarlet args = select text noblanks template value-of
	SESSION=$(echo "$REQUEST" | xmlstarlet sel -T -B -t -v '/_:result/_:listSession/_:token');
	if [ -z "$SESSION" ]; then
		# if there is not a sessionToken, echo the appropriate pieces of the request to a temp file and finish
		echo "$REQUEST" | xmlstarlet sel -T -B -t -v '//_:pid' | grep -E '[0-9]$' > /tmp/PID_LIST;
	else
		# if there is a sessionToken, echo the appropriate pieces of the request to a temp file and re-cur(l)
		echo "$REQUEST" | xmlstarlet sel -T -B -t -v '//_:pid' | grep -E '[0-9]$' > /tmp/PID_LIST;
		re-cur "$SESSION"
	fi
}

re-cur()
{
	URL="http://localhost:8080/fedora/objects?query=cDate%3E%3D";
	C_DATE="cDate%3E%3D""$RUN_TIME";
	M_DATE="%20mDate%3E%3D""$RUN_TIME";
	PIDS="%20pid%7Eutk.ir*";
	ARGS="&pid=true&resultFormat=xml&sessionToken=";
	SESSION=$1;
	REQUEST=$(curl -s "$URL""$C_DATE""$M_DATE""$PIDS""$ARGS""$SESSION")
	NEW_SESSION=$(echo "$REQUEST" | xmlstarlet sel -T -B -t -v '/_:result/_:listSession/_:token');
	if [ -z "$NEW_SESSION" ]; then
		# if there is not a sessionToken, echo the appropriate pieces of the request to a temp file and finish
		echo "$REQUEST" | xmlstarlet sel -T -B -t -v '//_:pid' | grep -E '[0-9]$' >> /tmp/PID_LIST;
	else
		# if there is a sessionToken, echo the appropriate pieces of the request to a temp file and re-cur(l)
		echo "$REQUEST" | xmlstarlet sel -T -B -t -v '//_:pid' | grep -E '[0-9]$' >> /tmp/PID_LIST;
		re-cur "$NEW_SESSION"
	fi
}

# Query Fedora for newly created or recently modified PIDs
echo "Querying Fedora..."
# a-curl will dump PIDs to a file (/tmp/PID_LIST)
a-curl

cat /tmp/PID_LIST

# Sleep for a second or two
echo "Why don't you rest for a second?"
sleep 2

# Begin updating Solr via Fedora GSearch
# The following curl command requires a username/password
echo "Updating Solr"
#shellcheck disable=SC2162
while read LINE;
do
	RELS_INT=$(curl -u fedoraAdmin:fedoraAdmin -s "http://localhost:8080/fedora/objects/"$LINE"/datastreams/RELS-INT/content")
	if echo "$RELS_INT" | grep -q '\[DefaulAccess\]'; then
		echo "updating a PID"
		(curl -u fedoraAdmin:fedoraAdmin -s -o /dev/null -X GET "http://localhost:8080/fedoragsearch/rest?operation=updateIndex&action=fromPid&value=$LINE")
	else
		if echo "$RELS_INT" | grep -q -v 'FULL_TEXT'; then
			echo "withdrawal: deleting PID from Solr"
			(curl -u fedoraAdmin:fedoraAdmin -s -o /dev/null -X GET "http://localhost:8080/fedoragsearch/rest?operation=updateIndex&action=deletePid&value=$LINE")
		else
			echo "embargo: deleting FULL_TEXT and updating Solr"
			(curl -u fedoraAdmin:fedoraAdmin -s -o /dev/null -X GET "http://localhost:8080/fedoragsearch/rest?operation=updateIndex&action=fromPid&value=$LINE")
			(curl http://localhost:8080/solr/update?commit=true -H 'Content-type:application/json' --data-binary '[{"PID":"$LINE", "FULL_TEXT_t": {"set":null}}]')
		fi
	fi
done < /tmp/PID_LIST

# Remove the temporary PID list
echo "All finished: removing the temporary PID_LIST"
rm -f /tmp/PID_LIST