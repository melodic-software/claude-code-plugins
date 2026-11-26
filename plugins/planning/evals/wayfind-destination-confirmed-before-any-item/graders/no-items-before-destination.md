---
type: regex
match: not_contains
pattern: 'work-items:track[\s`*"]*(?:(?:Arg|arg)(?:ument)?s[\s:=*`"]*)?(?:add|edit|link|start|done|publish-plan)\b|\b(?:Created|created):?\s+(?:the |decision |map )*(?:item|issue|map)?\s*["''‘“]|(?:^|[.!?;:,\n])(?:(?!\b(?:(?:No|no)|(?:Not|not)|(?:Never|never)|(?:Would|would)|(?:Could|could)|(?:Will|will)|(?:Shall|shall)|(?:Should|should)|(?:Can|can)|(?:Once|once)|(?:After|after)|(?:When|when)|(?:Before|before)|(?:If|if)|(?:Whether|whether)|(?:Nothing|nothing)|(?:Until|until))\b|n''t\b|''ll\b)[^.!?;:,\n])*?\b(?:(?:Created|created)|(?:Opened|opened)|(?:Filed|filed))\b(?:(?!\b(?:(?:No|no)|(?:Not|not)|(?:Would|would)|(?:Could|could)|(?:Will|will)|(?:Until|until))\b|n''t\b)[^.!?;:,\n]){0,40}?\b(?:(?:Map|map)|(?:Decision|decision) items?|(?:Items?|items?)|issues?)\b'
---
