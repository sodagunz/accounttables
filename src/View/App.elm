module View.App exposing (Config, view)

import Accounting exposing (FilterWindow, Movement, SortField)
import Auth exposing (AuthState(..))
import Html exposing (Html, button, div, h1, header, label, main_, option, p, section, select, span, strong, text)
import Html.Attributes exposing (class, type_, value)
import Html.Events exposing (onClick, onInput)
import Ledger
import Model exposing (MigrationState(..), Model, StorageMode(..), TutorialState(..))
import Util.Date exposing (DateDisplay)
import View.AuthStatus as AuthStatus
import View.LedgerAccess as LedgerAccess
import View.LedgerAccounts as LedgerAccounts
import View.MovementForm as MovementForm
import View.MovementTable as MovementTable


type alias Config msg =
    { localLedgerName : String
    , onReopenTutorial : msg
    , onDismissTutorialCompletion : msg
    , onSignIn : msg
    , onSignOut : msg
    , onDescription : String -> msg
    , onAmount : String -> msg
    , onAccount : String -> msg
    , onCreateAccount : msg
    , onCurrency : String -> msg
    , onDate : String -> msg
    , onMovementType : Accounting.MovementType -> msg
    , onSubmitMovement : msg
    , onCancelEdit : msg
    , onSelectFilter : FilterWindow -> msg
    , onToggleAccountFilter : String -> msg
    , onSelectDateDisplay : DateDisplay -> msg
    , onSelectDisplayCurrency : Accounting.Currency -> msg
    , onSelectSort : SortField -> msg
    , onExportCsv : msg
    , onExportXlsx : msg
    , onDeleteMovement : String -> msg
    , onEditMovement : String -> msg
    , onSelectLedger : String -> msg
    , onLedgerName : String -> msg
    , onSaveLedgerName : msg
    , onInviteEmail : String -> msg
    , onInvite : msg
    , onRemoveGuest : String -> msg
    , onAccountName : String -> msg
    , onAddAccount : msg
    , onDeleteAccount : String -> msg
    , onSelectMigrationLedger : String -> msg
    , onConfirmLocalMigration : msg
    , onSkipLocalMigration : msg
    }


view : Config msg -> Model -> Html msg
view config model =
    let
        rows : List Movement
        rows =
            Model.visibleMovements model

        isTutorialOpen : Bool
        isTutorialOpen =
            case model.tutorialState of
                TutorialOpen _ ->
                    True

                _ ->
                    False

        mainContent : List (Html msg)
        mainContent =
            [ reopenTutorialButton config model
            , tutorialCompletionBanner config model
            , migrationPrompt config model
            , localRiskBanner config model
            , div [ class "layout" ]
                [ div [ class "input-area" ]
                    [ MovementForm.view
                        { form = model.form
                        , accounts = Model.activeAccounts model
                        , exchangeRate = model.exchangeRate
                        , exchangeRateStatus = model.exchangeRateStatus
                        , zone = model.zone
                        , error = model.error
                        , onDescription = config.onDescription
                        , onAmount = config.onAmount
                        , onAccount = config.onAccount
                        , onCreateAccount = config.onCreateAccount
                        , onCurrency = config.onCurrency
                        , onDate = config.onDate
                        , onMovementType = config.onMovementType
                        , onSubmit = config.onSubmitMovement
                        , onCancel = config.onCancelEdit
                        }
                    ]
                , div [ class "admin-area" ]
                    [ adminArea config model
                    ]
                , div [ class "content-stack" ]
                    [ MovementTable.view
                        { expenses = rows
                        , accounts = Model.activeAccounts model
                        , filterWindow = model.filterWindow
                        , hiddenAccountIds = model.hiddenAccountIds
                        , dateDisplay = model.dateDisplay
                        , displayCurrency = model.displayCurrency
                        , sortField = model.sortField
                        , sortDirection = model.sortDirection
                        , onSelectFilter = config.onSelectFilter
                        , onToggleAccount = config.onToggleAccountFilter
                        , onSelectDateDisplay = config.onSelectDateDisplay
                        , onSelectDisplayCurrency = config.onSelectDisplayCurrency
                        , onSelectSort = config.onSelectSort
                        , onExportCsv = config.onExportCsv
                        , onExportXlsx = config.onExportXlsx
                        , onDelete = config.onDeleteMovement
                        , onEdit = config.onEditMovement
                        }
                    ]
                ]
            ]
    in
    div [ class "app" ]
        [ header [ class "topbar" ]
            [ div [ class "topbar__inner" ]
                [ div [ class "topbar__content" ]
                    [ div []
                        [ h1 [] [ text "accounttables" ] ]
                    , div [ class "topbar__actions" ]
                        [ if isTutorialOpen then
                            text ""

                          else
                            button [ class "topbar-setup-button", type_ "button", onClick config.onReopenTutorial ]
                                [ text "Configuracion inicial" ]
                        , AuthStatus.view
                            { authState = model.authState
                            , ledgerLoadState = model.ledgerLoadState
                            , onSignIn = config.onSignIn
                            , onSignOut = config.onSignOut
                            }
                        ]
                    ]
                ]
            ]
        , main_ [] mainContent
        ]


tutorialCompletionBanner : Config msg -> Model -> Html msg
tutorialCompletionBanner config model =
    if model.tutorialCompletionVisible then
        section [ class "tutorial-done-banner" ]
            [ strong [] [ text "Listo" ]
            , span [] [ text "Ya puedes empezar a registrar movimientos." ]
            , button [ type_ "button", onClick config.onDismissTutorialCompletion ] [ text "Cerrar" ]
            ]

    else
        text ""


reopenTutorialButton : Config msg -> Model -> Html msg
reopenTutorialButton config model =
    case model.tutorialState of
        TutorialOpen _ ->
            text ""

        _ ->
            section [ class "setup-shortcut" ]
                [ button [ class "setup-shortcut__button", type_ "button", onClick config.onReopenTutorial ]
                    [ text "Abrir configuracion inicial" ]
                ]


migrationPrompt : Config msg -> Model -> Html msg
migrationPrompt config model =
    case model.migrationState of
        NoMigration ->
            text ""

        PreparingMigration ->
            section [ class "migration-panel" ]
                [ strong [] [ text "Preparando sincronizacion" ]
                , p [] [ text "Estamos revisando tus libros de Firestore antes de subir los datos locales." ]
                ]

        UploadingMigration _ ->
            section [ class "migration-panel" ]
                [ strong [] [ text "Subiendo datos locales" ]
                , p [] [ text "Estamos mergeando tus cuentas y movimientos en Firestore." ]
                ]

        ChoosingMigration ledgers selectedLedgerId ->
            section [ class "migration-panel" ]
                [ strong [] [ text "Subir datos locales" ]
                , p [] [ text "Encontramos mas de un libro disponible. Elige donde quieres mergear las cuentas y movimientos guardados en este navegador." ]
                , label []
                    [ text "Libro destino"
                    , select [ value selectedLedgerId, onInput config.onSelectMigrationLedger ]
                        (List.map migrationLedgerOption ledgers)
                    ]
                , div [ class "migration-panel__actions" ]
                    [ button [ class "primary", type_ "button", onClick config.onConfirmLocalMigration ] [ text "Subir datos locales" ]
                    , button [ class "cancel-button", type_ "button", onClick config.onSkipLocalMigration ] [ text "Ahora no" ]
                    ]
                ]


migrationLedgerOption : Ledger.LedgerSummary -> Html msg
migrationLedgerOption ledger =
    option [ value ledger.id ] [ text ledger.name ]


localRiskBanner : Config msg -> Model -> Html msg
localRiskBanner config model =
    case model.authState of
        SignedIn _ ->
            text ""

        _ ->
            if model.storageMode == LocalOnly then
                let
                    hasLocalData : Bool
                    hasLocalData =
                        not (List.isEmpty model.events)
                            || not (List.isEmpty model.accounts)
                            || model.ledgerName
                            /= config.localLedgerName
                in
                section [ class "local-risk" ]
                    [ strong [] [ text "Modo local" ]
                    , span []
                        [ text
                            (if hasLocalData then
                                "Tus datos estan guardados solo en este navegador. Inicia sesion con Google para respaldo y sincronizacion."

                             else
                                "Puedes usar la app sin Google. Los datos locales pueden perderse si se borra el navegador o cambias de dispositivo."
                            )
                        ]
                    ]

            else
                text ""


adminArea : Config msg -> Model -> Html msg
adminArea config model =
    section [ class "panel admin-panel" ]
        [ Html.details [ class "admin-disclosure", Html.Attributes.id "admin-tool" ]
            [ Html.summary [ class "admin-disclosure__summary" ]
                [ span [] [ text "Configuracion del libro" ]
                , strong [] [ text "Administrar" ]
                ]
            , div [ class "admin-disclosure__content" ]
                [ LedgerAccess.view
                    { authState = model.authState
                    , ledgers = model.ledgers
                    , currentLedgerId = model.currentLedgerId
                    , ledgerName = model.ledgerName
                    , inviteEmail = model.inviteEmail
                    , error = model.ledgerError
                    , onSelectLedger = config.onSelectLedger
                    , onLedgerName = config.onLedgerName
                    , onSaveLedgerName = config.onSaveLedgerName
                    , onInviteEmail = config.onInviteEmail
                    , onInvite = config.onInvite
                    , onRemoveGuest = config.onRemoveGuest
                    }
                , LedgerAccounts.view
                    { accounts = Model.activeAccounts model
                    , newAccountName = model.newAccountName
                    , error = model.accountError
                    , onName = config.onAccountName
                    , onAdd = config.onAddAccount
                    , onDelete = config.onDeleteAccount
                    }
                ]
            ]
        ]
