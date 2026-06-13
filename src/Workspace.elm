module Workspace exposing
    ( LoadState(..)
    , Member
    , WorkspaceSummary
    , decodeWorkspace
    , encodeAccountCreate
    , encodeAccountDelete
    , encodeExpense
    , encodeGuestInvite
    , encodeGuestRemove
    , encodeWorkspaceName
    , encodeWorkspaceRequest
    )

import Accounting exposing (Account, Expense, currencyFromString, currencyToString)
import Json.Decode as Decode
import Json.Encode as Encode


type LoadState
    = NotLoaded
    | Loading
    | Loaded
    | LoadError String


type alias WorkspaceSummary =
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


encodeWorkspaceRequest : String -> Encode.Value
encodeWorkspaceRequest workspaceId =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId ) ]


encodeExpense : String -> Expense -> Encode.Value
encodeExpense workspaceId expense =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "expense", encodeExpenseRecord expense )
        ]


encodeAccountCreate : String -> String -> Encode.Value
encodeAccountCreate workspaceId name =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "name", Encode.string name )
        ]


encodeAccountDelete : String -> String -> Encode.Value
encodeAccountDelete workspaceId accountId =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "accountId", Encode.string accountId )
        ]


encodeGuestInvite : String -> String -> Encode.Value
encodeGuestInvite workspaceId email =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "email", Encode.string email )
        ]


encodeGuestRemove : String -> String -> Encode.Value
encodeGuestRemove workspaceId uid =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "uid", Encode.string uid )
        ]


encodeWorkspaceName : String -> String -> Encode.Value
encodeWorkspaceName workspaceId name =
    Encode.object
        [ ( "workspaceId", Encode.string workspaceId )
        , ( "name", Encode.string name )
        ]


encodeExpenseRecord : Expense -> Encode.Value
encodeExpenseRecord expense =
    Encode.object
        [ ( "id", Encode.string expense.id )
        , ( "description", Encode.string expense.description )
        , ( "accountId", Encode.string expense.accountId )
        , ( "accountName", Encode.string expense.accountName )
        , ( "inputAmount", Encode.float expense.inputAmount )
        , ( "inputCurrency", Encode.string (currencyToString expense.inputCurrency) )
        , ( "exchangeRate", Encode.float expense.exchangeRate )
        , ( "ars", Encode.float expense.ars )
        , ( "usd", Encode.float expense.usd )
        , ( "date", Encode.string expense.date )
        ]


decodeWorkspace : Decode.Value -> Result String { expenses : List Expense, accounts : List Account, workspaces : List WorkspaceSummary, currentWorkspaceId : String }
decodeWorkspace value =
    Decode.decodeValue workspacePayloadDecoder value
        |> Result.mapError Decode.errorToString


workspacePayloadDecoder : Decode.Decoder { expenses : List Expense, accounts : List Account, workspaces : List WorkspaceSummary, currentWorkspaceId : String }
workspacePayloadDecoder =
    Decode.field "status" Decode.string
        |> Decode.andThen
            (\status ->
                case status of
                    "loaded" ->
                        Decode.map4
                            (\workspaces currentWorkspaceId accounts expenses ->
                                { workspaces = workspaces
                                , currentWorkspaceId = currentWorkspaceId
                                , accounts = accounts
                                , expenses = expenses
                                }
                            )
                            (Decode.field "workspaces" (Decode.list workspaceSummaryDecoder))
                            (Decode.field "workspaceId" Decode.string)
                            (Decode.field "accounts" (Decode.list accountDecoder))
                            (Decode.field "expenses" (Decode.list expenseDecoder))

                    "error" ->
                        Decode.field "message" Decode.string
                            |> Decode.andThen Decode.fail

                    _ ->
                        Decode.fail ("Estado de workspace desconocido: " ++ status)
            )


accountDecoder : Decode.Decoder Account
accountDecoder =
    Decode.map3 Account
        (Decode.field "id" Decode.string)
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "deletedAt" Decode.string))


workspaceSummaryDecoder : Decode.Decoder WorkspaceSummary
workspaceSummaryDecoder =
    Decode.map4 WorkspaceSummary
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
        (\id description accountId accountName inputAmount inputCurrency exchangeRate ars ->
            \usd date deletedAt ->
                { id = id
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
        (Decode.field "description" Decode.string)
        (Decode.field "accountId" Decode.string)
        (Decode.field "accountName" Decode.string)
        (Decode.field "inputAmount" Decode.float)
        (Decode.field "inputCurrency" (Decode.map currencyFromString Decode.string))
        (Decode.field "exchangeRate" Decode.float)
        (Decode.field "ars" Decode.float)
        |> Decode.andThen
            (\buildExpense ->
                Decode.map3 buildExpense
                    (Decode.field "usd" Decode.float)
                    (Decode.field "date" Decode.string)
                    (Decode.maybe (Decode.field "deletedAt" Decode.string))
            )
