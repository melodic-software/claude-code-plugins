<!-- evidence-verification -->
### Verification evidence for {{head}}

{{summary}}

{{#criteria}}

{{criteria_table}}

{{/criteria}}
{{#record}}

| Record | |
|---|---|
| Verified by | {{verified_by}} |
| Verified at | {{verified_at}} |
| Issues found and resolution | {{issues}} |

{{/record}}
{{#inline}}
{{capture_line}}

{{capture_table}}

{{#video}}
{{video_ref}}

{{video_caption}}

{{/video}}
{{/inline}}
{{#section}}
<details>
<summary>{{section_title}}</summary>

{{section_text}}

{{#capture}}
{{capture_label}}

{{capture_image}}

{{/capture}}
</details>

{{/section}}
{{artifact_line}}

<sub>One comment per pull request, updated in place for each new head.</sub>
