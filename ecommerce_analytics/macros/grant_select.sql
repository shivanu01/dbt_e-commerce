{% macro grant_select(role)%}
    grant select on {{this}} torole {{role}}
{% endmacro %}