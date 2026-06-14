module Ledger exposing
    ( LedgerData
    , LedgerSummary
    , LoadState(..)
    , Member
    , decodeLedger
    , encodeAccountCreate
    , encodeAccountDelete
    , encodeExpense
    , encodeGuestInvite
    , encodeGuestRemove
    , encodeLedgerName
    , encodeLedgerRequest
    )

import Accounting exposing (Account, Expense, currencyFromString, currencyToString, movementTypeFromString, movementTypeToString)
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
    }


type alias Member =
    { uid : String
    , email : String
    , displayName : String
    }


type alias LedgerData =
    { events : List Event
    , expenses : List Expense
    , accounts : List Account
    , ledgers : List LedgerSummary
    , currentLedgerId : String
    , lastAccountId : Maybe String
    }


encodeLedgerRequest : String -> Encode.Value
encodeLedgerRequest ledgerId =
    Encode.object
        [ ( "ledgerId", Encode.string ledgerId ) ]


encodeExpense : String -> Expense -> Encode.Value
encodeExpense ledgerId expense =
    Encode.object
        [ ( "ledgerId", Encode.string ledgerId )
        , ( "expense", encodeExpenseRecord expense )
        ]


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


encodeExpenseRecord : Expense -> Encode.Value
encodeExpenseRecord expense =
    Encode.object
        [ ( "id", Encode.string expense.id )
        , ( "movementType", Encode.string (movementTypeToString expense.movementType) )
        , ( "description", encodeMaybeString expense.description )
        , ( "accountId", Encode.string expense.accountId )
        , ( "accountName", Encode.string expense.accountName )
        , ( "inputAmount", Encode.float expense.inputAmount )
        , ( "inputCurrency", Encode.string (currencyToString expense.inputCurrency) )
        , ( "exchangeRate", Encode.float expense.exchangeRate )
        , ( "ars", Encode.float expense.ars )
        , ( "usd", Encode.float expense.usd )
        , ( "date", Encode.string expense.date )
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
                            (Decode.field "expenses" (Decode.list expenseDecoder))
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
    Decode.map4 LedgerSummary
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.field "ownerUid" Decode.string)
        (Decode.field "members" (Decode.list memberDecoder))


memberDecoder : Decode.Decoder Member
memberDecoder =
    Decode.map3 Member
        (Decode.field "uid" Decode.string)
        (Decode.field "email" Decode.string)
        (Decode.field "displayName" Decode.string)


expenseDecoder : Decode.Decoder Expense
expenseDecoder =
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
            (\buildExpense ->
                Decode.map4 buildExpense
                    (Decode.field "ars" Decode.float)
                    (Decode.field "usd" Decode.float)
                    (Decode.field "date" Decode.string)
                    (Decode.maybe (Decode.field "deletedAt" Decode.string))
            )
