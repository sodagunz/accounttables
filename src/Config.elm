module Config exposing
    ( Messages
    , Ports
    , authUpdate
    , expenses
    , ledgerData
    , tutorial
    , view
    )

import Accounting exposing (FilterWindow, SortField)
import Events
import Json.Encode as Encode
import Ledger
import Model exposing (Model, TutorialState, TutorialStep)
import Tutorial
import Update.Auth as AuthUpdate
import Update.Expenses as Expenses
import Update.LedgerData as LedgerData
import Util.Date exposing (DateDisplay)
import View.App as AppView


type alias Messages msg =
    { reopenTutorial : msg
    , dismissTutorialCompletion : msg
    , signIn : msg
    , signOut : msg
    , description : String -> msg
    , amount : String -> msg
    , account : String -> msg
    , createAccount : msg
    , currency : String -> msg
    , date : String -> msg
    , movementType : Accounting.MovementType -> msg
    , submitExpense : msg
    , cancelEdit : msg
    , selectFilter : FilterWindow -> msg
    , toggleAccountFilter : String -> msg
    , selectDateDisplay : DateDisplay -> msg
    , selectDisplayCurrency : Accounting.Currency -> msg
    , selectSort : SortField -> msg
    , exportCsv : msg
    , exportXlsx : msg
    , deleteExpense : String -> msg
    , editExpense : String -> msg
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
    { showTutorialStep : Encode.Value -> Cmd msg
    , openDisclosure : String -> Cmd msg
    , focusElement : String -> Cmd msg
    , hideTutorial : () -> Cmd msg
    , saveTutorialState : Encode.Value -> Cmd msg
    , mergeLocalLedgerToFirestore : Encode.Value -> Cmd msg
    , prepareLocalMigration : () -> Cmd msg
    , loadLedgerData : Encode.Value -> Cmd msg
    , generateExpenseId : () -> Cmd msg
    , appendEvent : Encode.Value -> Cmd msg
    , saveLastAccount : String -> String -> Cmd msg
    }


view : Messages msg -> AppView.Config msg
view messages =
    { localLedgerName = Ledger.localLedgerName
    , onReopenTutorial = messages.reopenTutorial
    , onDismissTutorialCompletion = messages.dismissTutorialCompletion
    , onSignIn = messages.signIn
    , onSignOut = messages.signOut
    , onDescription = messages.description
    , onAmount = messages.amount
    , onAccount = messages.account
    , onCreateAccount = messages.createAccount
    , onCurrency = messages.currency
    , onDate = messages.date
    , onMovementType = messages.movementType
    , onSubmitExpense = messages.submitExpense
    , onCancelEdit = messages.cancelEdit
    , onSelectFilter = messages.selectFilter
    , onToggleAccountFilter = messages.toggleAccountFilter
    , onSelectDateDisplay = messages.selectDateDisplay
    , onSelectDisplayCurrency = messages.selectDisplayCurrency
    , onSelectSort = messages.selectSort
    , onExportCsv = messages.exportCsv
    , onExportXlsx = messages.exportXlsx
    , onDeleteExpense = messages.deleteExpense
    , onEditExpense = messages.editExpense
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


tutorial : Ports msg -> Tutorial.Config msg
tutorial ports =
    { showStep = ports.showTutorialStep
    , openDisclosure = ports.openDisclosure
    , focusElement = ports.focusElement
    , hide = ports.hideTutorial
    , saveState = ports.saveTutorialState
    }


ledgerData : Tutorial.Config msg -> Ports msg -> LedgerData.Config msg
ledgerData tutorialConfig ports =
    { navigateTutorial = Tutorial.tutorialNavigateCmd tutorialConfig
    , mergeLocalLedgerToFirestore =
        \ledgerId -> ports.mergeLocalLedgerToFirestore (Ledger.encodeLedgerRequest ledgerId)
    }


authUpdate : Tutorial.Config msg -> Ports msg -> AuthUpdate.Config msg
authUpdate tutorialConfig ports =
    { prepareLocalMigration = ports.prepareLocalMigration ()
    , loadLedgerData = \ledgerId -> ports.loadLedgerData (Ledger.encodeLedgerRequest ledgerId)
    , completeTutorial =
        Cmd.batch
            [ ports.hideTutorial ()
            , ports.saveTutorialState (Encode.string "completed")
            ]
    , tutorialAdvanceCmd = Tutorial.tutorialAdvanceCmd tutorialConfig
    , tutorialNavigateCmd = Tutorial.tutorialNavigateCmd tutorialConfig
    }


expenses : Tutorial.Config msg -> Ports msg -> Expenses.Config msg
expenses tutorialConfig ports =
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
    , navigateTutorial = Tutorial.tutorialNavigateTo tutorialConfig
    , completeTutorial =
        Cmd.batch
            [ ports.hideTutorial ()
            , ports.saveTutorialState (Encode.string "completed")
            ]
    }
