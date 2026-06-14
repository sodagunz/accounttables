module Events exposing
    ( Event(..)
    , MovementCreatedData
    , MovementDeletedData
    , MovementUpdatedData
    , eventDecoder
    , eventEncoder
    , eventSequence
    , eventTypeToString
    )

import Accounting exposing (Currency, MovementType(..), currencyFromString, currencyToString, movementTypeFromString, movementTypeToString)
import Json.Decode as Decode exposing (Decoder, decodeValue, field, float, int, list, map, maybe, string)
import Json.Decode.Pipeline exposing (required)
import Json.Encode as Encode


version : Int
version =
    1


type Event
    = MovementCreatedEvent Int MovementCreatedData
    | MovementDeletedEvent Int MovementDeletedData
    | MovementUpdatedEvent Int MovementUpdatedData


type alias MovementCreatedData =
    { id : String
    , movementType : MovementType
    , description : Maybe String
    , accountId : String
    , accountName : String
    , inputAmount : Float
    , inputCurrency : Currency
    , exchangeRate : Float
    , ars : Float
    , usd : Float
    , date : String
    }


type alias MovementDeletedData =
    { movementId : String }


type alias MovementUpdatedData =
    { movementId : String
    , changes : Encode.Value
    }


eventSequence : Event -> Int
eventSequence event =
    case event of
        MovementCreatedEvent seq _ ->
            seq

        MovementDeletedEvent seq _ ->
            seq

        MovementUpdatedEvent seq _ ->
            seq


eventTypeToString : Event -> String
eventTypeToString event =
    case event of
        MovementCreatedEvent _ _ ->
            "movement_created"

        MovementDeletedEvent _ _ ->
            "movement_deleted"

        MovementUpdatedEvent _ _ ->
            "movement_updated"


eventEncoder : Event -> Encode.Value
eventEncoder event =
    Encode.object
        [ ( "sequence", Encode.int (eventSequence event) )
        , ( "eventType", Encode.string (eventTypeToString event) )
        , ( "version", Encode.int version )
        , ( "data", dataEncoder event )
        ]


dataEncoder : Event -> Encode.Value
dataEncoder event =
    case event of
        MovementCreatedEvent _ data ->
            Encode.object
                [ ( "movement"
                  , Encode.object
                        [ ( "id", Encode.string data.id )
                        , ( "movementType", Encode.string (movementTypeToString data.movementType) )
                        , ( "description", encodeMaybeString data.description )
                        , ( "accountId", Encode.string data.accountId )
                        , ( "accountName", Encode.string data.accountName )
                        , ( "inputAmount", Encode.float data.inputAmount )
                        , ( "inputCurrency", Encode.string (currencyToString data.inputCurrency) )
                        , ( "exchangeRate", Encode.float data.exchangeRate )
                        , ( "ars", Encode.float data.ars )
                        , ( "usd", Encode.float data.usd )
                        , ( "date", Encode.string data.date )
                        ]
                  )
                ]

        MovementDeletedEvent _ data ->
            Encode.object
                [ ( "movementId", Encode.string data.movementId ) ]

        MovementUpdatedEvent _ data ->
            Encode.object
                [ ( "movementId", Encode.string data.movementId )
                , ( "changes", data.changes )
                ]


encodeMaybeString : Maybe String -> Encode.Value
encodeMaybeString maybeString =
    case maybeString of
        Just value ->
            Encode.string value

        Nothing ->
            Encode.null



-- Decoder for the envelope: { eventType, sequence, data, version }


eventDecoder : Decoder Event
eventDecoder =
    field "eventType" string
        |> Decode.andThen decodeEventByType


decodeEventByType : String -> Decoder Event
decodeEventByType eventType =
    let
        sequenceDecoder =
            field "sequence" int
    in
    case eventType of
        "movement_created" ->
            Decode.map2 MovementCreatedEvent
                sequenceDecoder
                movementCreatedDecoder

        "movement_deleted" ->
            Decode.map2 MovementDeletedEvent
                sequenceDecoder
                movementDeletedDecoder

        "movement_updated" ->
            Decode.map2 MovementUpdatedEvent
                sequenceDecoder
                movementUpdatedDecoder

        _ ->
            Decode.fail ("Unknown event type: " ++ eventType)


movementCreatedDecoder : Decoder MovementCreatedData
movementCreatedDecoder =
    field "data" (field "movement" movementDataDecoder)


movementDataDecoder : Decoder MovementCreatedData
movementDataDecoder =
    Decode.succeed MovementCreatedData
        |> required "id" string
        |> required "movementType" (Decode.map movementTypeFromString string)
        |> required "description" (maybe string)
        |> required "accountId" string
        |> required "accountName" string
        |> required "inputAmount" float
        |> required "inputCurrency" (Decode.map currencyFromString string)
        |> required "exchangeRate" float
        |> required "ars" float
        |> required "usd" float
        |> required "date" string


movementDeletedDecoder : Decoder MovementDeletedData
movementDeletedDecoder =
    field "data" <|
        Decode.map MovementDeletedData
            (field "movementId" string)


movementUpdatedDecoder : Decoder MovementUpdatedData
movementUpdatedDecoder =
    field "data" <|
        Decode.map2 MovementUpdatedData
            (field "movementId" string)
            (field "changes" Decode.value)
