module Update.Sorting exposing (defaultSortDirection, select, toggleDirection)

import Accounting exposing (SortDirection(..), SortField(..))


select :
    SortField
    -> { model | sortField : SortField, sortDirection : SortDirection }
    -> { model | sortField : SortField, sortDirection : SortDirection }
select sortField model =
    if model.sortField == sortField then
        { model | sortDirection = toggleDirection model.sortDirection }

    else
        { model | sortField = sortField, sortDirection = defaultSortDirection sortField }


toggleDirection : SortDirection -> SortDirection
toggleDirection sortDirection =
    case sortDirection of
        Ascending ->
            Descending

        Descending ->
            Ascending


defaultSortDirection : SortField -> SortDirection
defaultSortDirection sortField =
    case sortField of
        SortByDate ->
            Descending

        SortByAccount ->
            Ascending

        SortByDescription ->
            Ascending

        SortByExchangeRate ->
            Descending

        SortByPesos ->
            Descending

        SortByDollars ->
            Descending
