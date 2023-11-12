CMD=(aws imagebuilder list-images --owner Amazon --filters "name=type,values=DOCKER")

RET=$("${CMD[@]}")
while true; do
    OUTPUT=$(echo "$RET" | jq ".imageVersionList[] | .arn")
    if [ "$OUTPUT" != "" ]; then
        echo "$OUTPUT"
    fi

    NEXT_TOKEN=$(echo "$RET" | jq -r 'if has("nextToken") then .nextToken end')
    if [ "$NEXT_TOKEN" == "" ]; then
        break
    fi

    RET=$("${CMD[@]}" --next-token "$NEXT_TOKEN")
done