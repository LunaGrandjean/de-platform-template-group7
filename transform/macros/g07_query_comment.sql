{#- Step 9: the query comment dbt puts on every job, as JSON, so that
    `query-comment.job-label: true` (dbt_project.yml) turns it into job labels.
    Same four keys as infra/terraform/labels.tf, plus resource (model, test,
    operation) so a build's cost splits into building and testing.
    dbt lowercases values and replaces anything outside [a-z0-9_-]. -#}
{% macro g07_query_comment(node) -%}
    {%- set labels = {
        "group": "g07",
        "env": target.name,
        "component": "dbt",
        "layer": "none",
        "resource": "operation",
    } -%}
    {%- if node is not none -%}
        {%- do labels.update({"resource": node.resource_type}) -%}
        {%- if node.resource_type == "model" -%}
            {%- do labels.update({"layer": node.config.schema or "none"}) -%}
        {%- endif -%}
    {%- endif -%}
    {{- return(tojson(labels)) -}}
{%- endmacro %}
