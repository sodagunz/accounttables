module Projector exposing (projectEvents)

import Accounting exposing (Movement)
import Events exposing (Event(..), MovementCreatedData, MovementUpdatedData, eventSequence)


projectEvents : List Event -> List Movement
projectEvents events =
    List.foldl applyEvent [] (List.sortBy eventSequence events)


applyEvent : Event -> List Movement -> List Movement
applyEvent event movements =
    case event of
        MovementCreatedEvent _ data ->
            movementCreated data :: movements

        MovementDeletedEvent _ data ->
            List.map (markDeleted data.movementId) movements

        MovementUpdatedEvent _ data ->
            List.map (applyUpdate data) movements


movementCreated : MovementCreatedData -> Movement
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


markDeleted : String -> Movement -> Movement
markDeleted movementId movement =
    if movement.id == movementId then
        { movement | deletedAt = Just "deleted" }

    else
        movement


applyUpdate : MovementUpdatedData -> Movement -> Movement
applyUpdate data movement =
    if movement.id == data.movementId then
        { id = data.movementId
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
        , deletedAt = movement.deletedAt
        }

    else
        movement
