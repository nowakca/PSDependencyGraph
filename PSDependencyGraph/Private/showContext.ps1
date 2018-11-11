function showContext {
    <#
    .DESCRIPTION
    Given a context object, print out its current state and Context

    #>

    [CmdletBinding()]
    Param(
        # The current context tracking object
        $context,

        # The current state tracking object
        $state
    )

    if ($context -and $context.count -gt 0) {
        write-verbose "State -> $state  $( ($context.Peek()) | ConvertTo-Json -Compress ) "
    } else {
        write-verbose "State -> $state  (no context)"
    }
}

