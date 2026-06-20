module Ledger exposing
    ( LedgerData
    , LedgerSummary
    , LoadState(..)
    , Member
    , decodeLedger
    , decodeLedgerSummaries
    , encodeAccountCreate
    , encodeAccountDelete
    , encodeGuestInvite
    , encodeGuestRemove
    , encodeLedgerName
    , encodeLedgerRequest
    , ensureLocalLedger
    , localLedgerId
    , localLedgerName
    )

import Accounting exposing (Account, Movement, currencyFromString, movementTypeFromString)
import Events exposing (Event)
import Json.Decode as Decode
import Json.Encode as Encode


type LoadState
    = NotLoaded
    | Loading
    | Loaded
    | LoadError String


type alias LedgerSummary =
    { id : String
    , name : String
    , ownerUid : String
    , members : List Member
    , invitedEmails : List String
    }


type alias Member =
    { uid : String
    , email : String
    , displayName : String
    }


type alias LedgerData =
    { events : List Event
    , expenses : List Movement
    , accounts : List Account
    , ledgers : List LedgerSummary
    , currentLedgerId : String
    , lastAccountId : Maybe String
    }


localLedgerId : String
localLedgerId =
    "local"


localLedgerName : String
localLedgerName =
    "Libro contable de desconocido"


ensureLocalLedger :
    storageMode
    ->
        { model
            | currentLedgerId : String
            , storageMode : storageMode
            , ledgerLoadState : LoadState
            , ledgerName : String
            , ledgers : List LedgerSummary
        }
    ->
        { model
            | currentLedgerId : String
            , storageMode : storageMode
            , ledgerLoadState : LoadState
            , ledgerName : String
            , ledgers : List LedgerSummary
        }
ensureLocalLedger localOnly model =
    if model.currentLedgerId == localLedgerId then
        { model
            | storageMode = localOnly
            , ledgerLoadState = Loaded
        }

    else
        { model
            | storageMode = localOnly
            , ledgerLoadState = Loaded
            , currentLedgerId = localLedgerId
            , ledgerName = localLedgerName
            , ledgers =
                [ { id = localLedgerId
                  , name = localLedgerName
                  , ownerUid = ""
                  , members = []
                  , invitedEmails = []
                  }
                ]
        }


encodeLedgerRequest : String -> Encode.Value
encodeLedgerRequest ledgerId =
    Encode.object
        [ ( "ledgerId", Encode.string ledgerId ) ]


encodeAccountCreate : String -> String -> Encode.Value
encodeAccountCreate ledgerId name =
    Encode.object
        [ ( "ledgerId", Encode.string ledgerId )
        , ( "name", Encode.string name )
        ]


encodeAccountDelete : String -> String -> Encode.Value
encodeAccountDelete ledgerId accountId =
    Encode.object
        [ ( "ledgerId", Encode.string ledgerId )
        , ( "accountId", Encode.string accountId )
        ]


encodeGuestInvite : String -> String -> Encode.Value
encodeGuestInvite ledgerId email =
    Encode.object
        [ ( "ledgerId", Encode.string ledgerId )
        , ( "email", Encode.string email )
        ]


encodeGuestRemove : String -> String -> Encode.Value
encodeGuestRemove ledgerId uid =
    Encode.object
        [ ( "ledgerId", Encode.string ledgerId )
        , ( "uid", Encode.string uid )
        ]


encodeLedgerName : String -> String -> Encode.Value
encodeLedgerName ledgerId name =
    Encode.object
        [ ( "ledgerId", Encode.string ledgerId )
        , ( "name", Encode.string name )
        ]


encodeMaybeString : Maybe String -> Encode.Value
encodeMaybeString maybeString =
    case maybeString of
        Just value ->
            Encode.string value

        Nothing ->
            Encode.null


decodeLedger : Decode.Value -> Result String LedgerData
decodeLedger value =
    Decode.decodeValue ledgerPayloadDecoder value
        |> Result.mapError Decode.errorToString


decodeLedgerSummaries : Decode.Value -> Result String (List LedgerSummary)
decodeLedgerSummaries value =
    Decode.decodeValue (Decode.field "ledgers" (Decode.list ledgerSummaryDecoder)) value
        |> Result.mapError Decode.errorToString


ledgerPayloadDecoder : Decode.Decoder LedgerData
ledgerPayloadDecoder =
    Decode.field "status" Decode.string
        |> Decode.andThen
            (\status ->
                case status of
                    "loaded" ->
                        Decode.map6
                            (\ledgers currentLedgerId accounts expenses lastAccountId events ->
                                { ledgers = ledgers
                                , currentLedgerId = currentLedgerId
                                , accounts = accounts
                                , expenses = expenses
                                , lastAccountId = lastAccountId
                                , events = events
                                }
                            )
                            (Decode.field "ledgers" (Decode.list ledgerSummaryDecoder))
                            (Decode.field "ledgerId" Decode.string)
                            (Decode.field "accounts" (Decode.list accountDecoder))
                            (Decode.field "expenses" (Decode.list movementDecoder))
                            (Decode.maybe (Decode.field "lastAccountId" Decode.string))
                            (Decode.field "events" (Decode.list Events.eventDecoder))

                    "error" ->
                        Decode.field "message" Decode.string
                            |> Decode.andThen Decode.fail

                    _ ->
                        Decode.fail ("Estado de libro contable desconocido: " ++ status)
            )


accountDecoder : Decode.Decoder Account
accountDecoder =
    Decode.map3 Account
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "deletedAt" Decode.string))


ledgerSummaryDecoder : Decode.Decoder LedgerSummary
ledgerSummaryDecoder =
    Decode.map5 LedgerSummary
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "ownerUid" Decode.string)
        (Decode.field "members" (Decode.list memberDecoder))
        (Decode.maybe (Decode.field "invitedEmails" (Decode.list Decode.string))
            |> Decode.map (Maybe.withDefault [])
        )


memberDecoder : Decode.Decoder Member
memberDecoder =
    Decode.map3 Member
        (Decode.field "uid" Decode.string)
        (Decode.field "email" Decode.string)
        (Decode.field "displayName" Decode.string)


movementDecoder : Decode.Decoder Movement
movementDecoder =
    Decode.map8
        (\id movementType description accountId accountName inputAmount inputCurrency exchangeRate ->
            \ars usd date deletedAt ->
                { id = id
                , movementType = movementType
                , description = description
                , accountId = accountId
                , accountName = accountName
                , inputAmount = inputAmount
                , inputCurrency = inputCurrency
                , exchangeRate = exchangeRate
                , ars = ars
                , usd = usd
                , date = date
                , deletedAt = deletedAt
                }
        )
        (Decode.field "id" Decode.string)
        (Decode.field "movementType" (Decode.map movementTypeFromString Decode.string))
        (Decode.field "description" (Decode.nullable Decode.string))
        (Decode.field "accountId" Decode.string)
        (Decode.field "accountName" Decode.string)
        (Decode.field "inputAmount" Decode.float)
        (Decode.field "inputCurrency" (Decode.map currencyFromString Decode.string))
        (Decode.field "exchangeRate" Decode.float)
        |> Decode.andThen
            (\buildMovement ->
                Decode.map4 buildMovement
                    (Decode.field "ars" Decode.float)
                    (Decode.field "usd" Decode.float)
                    (Decode.field "date" Decode.string)
                    (Decode.maybe (Decode.field "deletedAt" Decode.string))
            )
