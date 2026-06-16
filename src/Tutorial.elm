module Tutorial exposing
    ( actionDecoder
    , encodeStep
    , focusSelector
    , nextStep
    , openDisclosureIds
    , prepareState
    , prepareStep
    , previousStep
    , reopenedStep
    , stepAfterAccounts
    , targetSelector
    )

import Accounting
import Auth exposing (AuthState(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (Model, TutorialState(..), TutorialStep(..))


actionDecoder : Decode.Decoder String
actionDecoder =
    Decode.field "action" Decode.string


encodeStep : Model -> TutorialStep -> Encode.Value
encodeStep model step =
    Encode.object
        [ ( "step", Encode.string (stepName step) )
        , ( "selector", Encode.string (targetSelector model step) )
        , ( "title", Encode.string "" )
        , ( "description", Encode.string (stepText step) )
        , ( "side", Encode.string (stepSide step) )
        , ( "align", Encode.string "start" )
        , ( "showBack", Encode.bool (showBack step) )
        , ( "showNext", Encode.bool (showNext step) )
        , ( "showSkip", Encode.bool (showSkip step) )
        , ( "done", Encode.bool (doneButton step) )
        , ( "allowTargetClick", Encode.bool (allowsTargetClick step) )
        , ( "openDisclosures", Encode.list Encode.string (openDisclosureIds step) )
        ]


targetSelector : Model -> TutorialStep -> String
targetSelector model step =
    case step of
        SignInStep ->
            "[data-tutorial=\"sign-in\"]"

        AccountsStep ->
            "[data-tutorial=\"account-form\"]"

        CollaboratorsStep ->
            "[data-tutorial=\"invite-email\"]"

        FirstExpenseStep ->
            "[data-tutorial=\"movement-form\"]"

        DeleteExpenseStep ->
            case model.tutorialExpenseId of
                Just expenseId ->
                    "[data-tutorial=\"delete-" ++ expenseId ++ "\"]"

                Nothing ->
                    "[data-tutorial=\"movement-form\"]"


focusSelector : Model -> TutorialStep -> String
focusSelector model step =
    case step of
        FirstExpenseStep ->
            "[data-tutorial=\"movement-amount\"]"

        _ ->
            targetSelector model step


prepareState : Model -> Model
prepareState model =
    case model.tutorialState of
        TutorialOpen step ->
            prepareStep step model

        _ ->
            model


prepareStep : TutorialStep -> Model -> Model
prepareStep step model =
    case step of
        FirstExpenseStep ->
            prefillExpenseForm model

        _ ->
            model


nextStep : TutorialStep -> Maybe TutorialStep
nextStep step =
    case step of
        SignInStep ->
            Just AccountsStep

        AccountsStep ->
            Just CollaboratorsStep

        CollaboratorsStep ->
            Just FirstExpenseStep

        FirstExpenseStep ->
            Just DeleteExpenseStep

        DeleteExpenseStep ->
            Nothing


previousStep : TutorialStep -> TutorialStep
previousStep step =
    case step of
        SignInStep ->
            SignInStep

        AccountsStep ->
            SignInStep

        CollaboratorsStep ->
            AccountsStep

        FirstExpenseStep ->
            CollaboratorsStep

        DeleteExpenseStep ->
            FirstExpenseStep


reopenedStep : Model -> TutorialStep
reopenedStep model =
    if List.isEmpty (Model.activeAccounts model) then
        AccountsStep

    else
        stepAfterAccounts model


stepAfterAccounts : Model -> TutorialStep
stepAfterAccounts model =
    case model.authState of
        SignedIn _ ->
            CollaboratorsStep

        _ ->
            FirstExpenseStep


openDisclosureIds : TutorialStep -> List String
openDisclosureIds step =
    case step of
        AccountsStep ->
            [ "admin-tool", "accounts-tool" ]

        CollaboratorsStep ->
            [ "admin-tool", "members-tool" ]

        _ ->
            []


prefillExpenseForm : Model -> Model
prefillExpenseForm model =
    let
        accountId =
            case model.form.accountId of
                "" ->
                    Model.activeAccounts model
                        |> List.head
                        |> Maybe.map .id
                        |> Maybe.withDefault ""

                selectedAccountId ->
                    selectedAccountId

        form =
            model.form
    in
    { model
        | form =
            { form
                | amount = "1000"
                , description = "Venta de prueba"
                , accountId = accountId
                , movementType = Accounting.IncomeMovement
                , editingId = Nothing
            }
    }


stepText : TutorialStep -> String
stepText step =
    case step of
        SignInStep ->
            "Para empezar, inicia sesion con Google. Si no quieres sincronizar, puedes saltar este paso."

        AccountsStep ->
            "Crea una cuenta para registrar movimientos. Dale un nombre y agregala."

        CollaboratorsStep ->
            "Invita a alguien por email para trabajar juntos. Tambien puedes hacerlo despues."

        FirstExpenseStep ->
            "Registra tu primer movimiento. El importe y la descripcion ya estan completos. Presiona Guardar."

        DeleteExpenseStep ->
            "Perfecto. Ahora borremos este movimiento de prueba para que todo quede limpio. Presiona el boton de eliminar."


stepName : TutorialStep -> String
stepName step =
    case step of
        SignInStep ->
            "sign-in"

        AccountsStep ->
            "accounts"

        CollaboratorsStep ->
            "collaborators"

        FirstExpenseStep ->
            "first-expense"

        DeleteExpenseStep ->
            "delete-expense"


stepSide : TutorialStep -> String
stepSide step =
    case step of
        SignInStep ->
            "bottom"

        AccountsStep ->
            "right"

        CollaboratorsStep ->
            "right"

        FirstExpenseStep ->
            "right"

        DeleteExpenseStep ->
            "left"


showBack : TutorialStep -> Bool
showBack step =
    step /= SignInStep


showNext : TutorialStep -> Bool
showNext step =
    step == CollaboratorsStep


showSkip : TutorialStep -> Bool
showSkip step =
    case step of
        AccountsStep ->
            False

        DeleteExpenseStep ->
            False

        _ ->
            True


doneButton : TutorialStep -> Bool
doneButton _ =
    False


allowsTargetClick : TutorialStep -> Bool
allowsTargetClick step =
    case step of
        CollaboratorsStep ->
            False

        DeleteExpenseStep ->
            True

        _ ->
            True
