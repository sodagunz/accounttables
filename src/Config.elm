module Config exposing
    ( Messages
    , Ports
    , authUpdate
    , ledgerData
    , movements
    , view
    )

import Accounting exposing (FilterWindow, SortField)
import Events
import Json.Encode as Encode
import Ledger
import Model exposing (ViewMode)
import Update.Auth as AuthUpdate
import Update.LedgerData as LedgerData
import Update.Movements as Movements
import Util.Date exposing (DateDisplay)
import View.App as AppView


type alias Messages msg =
    { toggleColorScheme : msg
    , signIn : msg
    , signOut : msg
    , description : String -> msg
    , amount : String -> msg
    , account : String -> msg
    , createAccount : msg
    , currency : String -> msg
    , date : String -> msg
    , movementType : Accounting.MovementType -> msg
    , relatedToInvoice : Bool -> msg
    , documentNumber : String -> msg
    , allocationTarget : String -> Bool -> msg
    , submitMovement : msg
    , cancelEdit : msg
    , selectFilter : FilterWindow -> msg
    , toggleAccountFilter : String -> msg
    , selectDateDisplay : DateDisplay -> msg
    , selectDisplayCurrency : Accounting.Currency -> msg
    , toggleShowInputAmountColumn : msg
    , toggleShowExchangeRateColumn : msg
    , selectSort : SortField -> msg
    , exportCsv : msg
    , exportXlsx : msg
    , exportInvoicesCsv : msg
    , exportInvoicesXlsx : msg
    , selectViewMode : ViewMode -> msg
    , deleteMovement : String -> msg
    , editMovement : String -> msg
    , selectLedger : String -> msg
    , ledgerName : String -> msg
    , saveLedgerName : msg
    , inviteEmail : String -> msg
    , invite : msg
    , removeGuest : String -> msg
    , accountName : String -> msg
    , addAccount : msg
    , deleteAccount : String -> msg
    , selectMigrationLedger : String -> msg
    , confirmLocalMigration : msg
    , skipLocalMigration : msg
    }


type alias Ports msg =
    { mergeLocalLedgerToFirestore : Encode.Value -> Cmd msg
    , prepareLocalMigration : () -> Cmd msg
    , loadLedgerData : Encode.Value -> Cmd msg
    , generateExpenseId : () -> Cmd msg
    , appendEvent : Encode.Value -> Cmd msg
    , saveLastAccount : String -> String -> Cmd msg
    }


view : Messages msg -> AppView.Config msg
view messages =
    { localLedgerName = Ledger.localLedgerName
    , onToggleColorScheme = messages.toggleColorScheme
    , onSignIn = messages.signIn
    , onSignOut = messages.signOut
    , onDescription = messages.description
    , onAmount = messages.amount
    , onAccount = messages.account
    , onCreateAccount = messages.createAccount
    , onCurrency = messages.currency
    , onDate = messages.date
    , onMovementType = messages.movementType
    , onRelatedToInvoice = messages.relatedToInvoice
    , onDocumentNumber = messages.documentNumber
    , onToggleAllocationTarget = messages.allocationTarget
    , onSubmitMovement = messages.submitMovement
    , onCancelEdit = messages.cancelEdit
    , onSelectFilter = messages.selectFilter
    , onToggleAccountFilter = messages.toggleAccountFilter
    , onSelectDateDisplay = messages.selectDateDisplay
    , onSelectDisplayCurrency = messages.selectDisplayCurrency
    , onToggleShowInputAmountColumn = messages.toggleShowInputAmountColumn
    , onToggleShowExchangeRateColumn = messages.toggleShowExchangeRateColumn
    , onSelectSort = messages.selectSort
    , onExportCsv = messages.exportCsv
    , onExportXlsx = messages.exportXlsx
    , onExportInvoicesCsv = messages.exportInvoicesCsv
    , onExportInvoicesXlsx = messages.exportInvoicesXlsx
    , onSelectViewMode = messages.selectViewMode
    , onDeleteMovement = messages.deleteMovement
    , onEditMovement = messages.editMovement
    , onSelectLedger = messages.selectLedger
    , onLedgerName = messages.ledgerName
    , onSaveLedgerName = messages.saveLedgerName
    , onInviteEmail = messages.inviteEmail
    , onInvite = messages.invite
    , onRemoveGuest = messages.removeGuest
    , onAccountName = messages.accountName
    , onAddAccount = messages.addAccount
    , onDeleteAccount = messages.deleteAccount
    , onSelectMigrationLedger = messages.selectMigrationLedger
    , onConfirmLocalMigration = messages.confirmLocalMigration
    , onSkipLocalMigration = messages.skipLocalMigration
    }


ledgerData : Ports msg -> LedgerData.Config msg
ledgerData ports =
    { mergeLocalLedgerToFirestore =
        \ledgerId -> ports.mergeLocalLedgerToFirestore (Ledger.encodeLedgerRequest ledgerId)
    }


authUpdate : Ports msg -> AuthUpdate.Config msg
authUpdate ports =
    { prepareLocalMigration = ports.prepareLocalMigration ()
    , loadLedgerData = \ledgerId -> ports.loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
    }


movements : Ports msg -> Movements.Config msg
movements ports =
    { generateExpenseId = ports.generateExpenseId ()
    , appendEvent =
        \ledgerId event ->
            ports.appendEvent
                (Encode.object
                    [ ( "ledgerId", Encode.string ledgerId )
                    , ( "event", Events.eventEncoder event )
                    ]
                )
    , saveLastAccount = ports.saveLastAccount
    }
