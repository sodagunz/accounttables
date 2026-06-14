module Projector exposing
    ( projectEvents
    )

import Accounting exposing (Expense)
import Events exposing (Event(..), MovementCreatedData, MovementDeletedData, MovementUpdatedData, eventSequence)


projectEvents : List Event -> List Expense
projectEvents events =
    List.foldl applyEvent [] (List.sortBy eventSequence events)


applyEvent : Event -> List Expense -> List Expense
applyEvent event expenses =
    case event of
        MovementCreatedEvent _ data ->
            movementCreated data :: expenses

        MovementDeletedEvent _ data ->
            List.map (markDeleted data.movementId) expenses

        MovementUpdatedEvent _ _ ->
            expenses


movementCreated : MovementCreatedData -> Expense
movementCreated data =
    { id = data.id
    , movementType = data.movementType
    , description = data.description
    , accountId = data.accountId
    , accountName = data.accountName
    , inputAmount = data.inputAmount
    , inputCurrency = data.inputCurrency
    , exchangeRate = data.exchangeRate
    , ars = data.ars
    , usd = data.usd
    , date = data.date
    , deletedAt = Nothing
    }


markDeleted : String -> Expense -> Expense
markDeleted movementId expense =
    if expense.id == movementId then
        { expense | deletedAt = Just "deleted" }

    else
        expense
