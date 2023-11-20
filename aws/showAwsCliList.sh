#CMD=(aws imagebuilder list-images --owner Amazon)
#LIST_NAME=imageVersionList
#CONDITIONS='.type == "DOCKER"'
CMD=(aws imagebuilder list-components --owner Amazon)
LIST_NAME=componentVersionList
CONDITIONS='.name | contains("corretto")'

RET=$("${CMD[@]}")
while true; do
    OUTPUT=$(echo "$RET" | jq ".$LIST_NAME[] | select($CONDITIONS) | .arn")
    if [ "$OUTPUT" != "" ]; then
        echo "$OUTPUT"
    fi

    NEXT_TOKEN=$(echo "$RET" | jq -r 'if has("nextToken") then .nextToken else "" end')
    if [ "$NEXT_TOKEN" == "" ]; then
        break
    fi

    RET=$("${CMD[@]}" --next-token "$NEXT_TOKEN")
done