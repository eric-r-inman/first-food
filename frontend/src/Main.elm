module Main exposing (main)

{-| Browser map editor for the empire-builder game board.

The board is a base terrain grid plus a stack of overlay layers (resources,
landmarks, buildings, units). The overlays are data-driven: a new layer is one
entry in `overlayTitles` (plus its data file, CLI feed, and editor page) — no
structural change here. The editor renders a movable viewport so the DOM stays
small at any map size, and maps save/load every layer as JSON.

-}

import Array exposing (Array)
import Browser
import Browser.Events
import Dict exposing (Dict)
import File exposing (File)
import File.Download as Download
import File.Select as Select
import Html exposing (Html, a, button, div, input, span, text)
import Html.Attributes as A
import Html.Events exposing (onClick, onInput, onMouseDown, onMouseEnter)
import Http
import Json.Decode as D
import Json.Encode as E
import Task
import Time



-- A keyed, colored glyph: terrain and every overlay share this shape.


type alias Terrain =
    { id : String
    , key : Char
    , glyph : String
    , color : String
    }


terrainDecoder : D.Decoder Terrain
terrainDecoder =
    D.map4 Terrain
        (D.field "id" D.string)
        (D.field "key" (D.string |> D.map firstChar))
        (D.field "glyph" D.string)
        (D.field "color" D.string)


firstChar : String -> Char
firstChar s =
    String.uncons s |> Maybe.map Tuple.first |> Maybe.withDefault ' '



-- MAP / GRID


type alias MapData =
    { width : Int
    , height : Int
    , rows : Array (Array Char)
    }


makeMap : Int -> Int -> Char -> MapData
makeMap w h fill =
    { width = w
    , height = h
    , rows = Array.repeat h (Array.repeat w fill)
    }


getCell : Int -> Int -> MapData -> Maybe Char
getCell x y m =
    Array.get y m.rows |> Maybe.andThen (Array.get x)


setCell : Int -> Int -> Char -> MapData -> MapData
setCell x y c m =
    case Array.get y m.rows of
        Just row ->
            { m | rows = Array.set y (Array.set x c row) m.rows }

        Nothing ->
            m


floodFill : Int -> Int -> Char -> MapData -> MapData
floodFill x y replacement m =
    case getCell x y m of
        Just target ->
            if target == replacement then
                m

            else
                floodLoop replacement target [ ( x, y ) ] m

        Nothing ->
            m


floodLoop : Char -> Char -> List ( Int, Int ) -> MapData -> MapData
floodLoop replacement target stack m =
    case stack of
        [] ->
            m

        ( cx, cy ) :: rest ->
            if getCell cx cy m == Just target then
                floodLoop replacement
                    target
                    (( cx - 1, cy ) :: ( cx + 1, cy ) :: ( cx, cy - 1 ) :: ( cx, cy + 1 ) :: rest)
                    (setCell cx cy replacement m)

            else
                floodLoop replacement target rest m


rowsFromStrings : List String -> Array (Array Char)
rowsFromStrings rows =
    rows |> List.map (String.toList >> Array.fromList) |> Array.fromList


rowsToStrings : MapData -> List String
rowsToStrings m =
    m.rows |> Array.toList |> List.map (Array.toList >> String.fromList)



-- OVERLAYS


{-| An empty overlay cell (nothing placed) is stored as a space.
-}
empty : Char
empty =
    ' '


{-| The overlay layers, ordered bottom to top. Adding a layer is a matter of
adding its title here (and shipping its data file, CLI feed, and editor page).
Climate sits low as an environmental base; weather sits on top as the
atmospheric layer.
-}
overlayTitles : List String
overlayTitles =
    [ "climate", "resources", "landmarks", "buildings", "units", "weather" ]


type alias Overlay =
    { title : String
    , url : String
    , field : String
    , editorHref : String
    , palette : List Terrain
    , byKey : Dict Char Terrain
    , grid : MapData
    , active : Char
    , rotation : Bool
    }


newOverlay : String -> Overlay
newOverlay title =
    { title = title
    , url = title ++ ".json"
    , field = title
    , editorHref = "/" ++ title ++ ".html"
    , palette = []
    , byKey = Dict.empty
    , grid = makeMap 64 40 empty
    , active = empty
    , rotation = True
    }


getOverlay : Int -> List Overlay -> Maybe Overlay
getOverlay i overlays =
    List.drop i overlays |> List.head


updateOverlay : Int -> (Overlay -> Overlay) -> List Overlay -> List Overlay
updateOverlay i f overlays =
    List.indexedMap
        (\j o ->
            if i == j then
                f o

            else
                o
        )
        overlays



-- MODEL


type Tool
    = Paint
    | Fill
    | Eyedropper


type Layer
    = TerrainLayer
    | OverlayLayer Int


type alias Snapshot =
    { terrain : MapData, overlays : List MapData }


type alias Model =
    { palette : List Terrain
    , byKey : Dict Char Terrain
    , map : MapData
    , active : Char
    , overlays : List Overlay
    , terrainRotation : Bool
    , tick : Int
    , name : String
    , tool : Tool
    , layer : Layer
    , vx : Int
    , vy : Int
    , cursor : Maybe ( Int, Int )
    , history : List Snapshot
    , future : List Snapshot
    , status : String
    , newW : String
    , newH : String
    , painting : Bool
    }


viewportW : Int
viewportW =
    72


viewportH : Int
viewportH =
    36


defaultFill : Char
defaultFill =
    'g'


grasslandKey : Model -> Char
grasslandKey model =
    model.palette
        |> List.filter (\t -> t.id == "grassland")
        |> List.head
        |> Maybe.map .key
        |> Maybe.withDefault defaultFill


init : () -> ( Model, Cmd Msg )
init _ =
    let
        overlays =
            List.map newOverlay overlayTitles
    in
    ( { palette = []
      , byKey = Dict.empty
      , map = makeMap 64 40 defaultFill
      , active = defaultFill
      , overlays = overlays
      , terrainRotation = True
      , tick = 0
      , name = "untitled"
      , tool = Paint
      , layer = TerrainLayer
      , vx = 0
      , vy = 0
      , cursor = Nothing
      , history = []
      , future = []
      , status = "loading palettes…"
      , newW = "64"
      , newH = "40"
      , painting = False
      }
    , Cmd.batch
        (Http.get { url = "palette.json", expect = Http.expectJson GotPalette (D.field "terrain" (D.list terrainDecoder)) }
            :: List.indexedMap
                (\i o -> Http.get { url = o.url, expect = Http.expectJson (GotOverlay i) (D.field o.field (D.list terrainDecoder)) })
                overlays
        )
    )



-- UPDATE


type Msg
    = GotPalette (Result Http.Error (List Terrain))
    | GotOverlay Int (Result Http.Error (List Terrain))
    | SelectTerrain Char
    | SelectOverlay Int Char
    | SetLayer Layer
    | ToggleTerrainRotation
    | ToggleOverlayRotation Int
    | Tick
    | SelectTool Tool
    | CellMouseDown Int Int
    | CellMouseEnter Int Int
    | StopPaint
    | Pan Int Int
    | SetNewW String
    | SetNewH String
    | NewMap
    | Undo
    | Redo
    | SaveMap
    | LoadRequested
    | FileSelected File
    | FileLoaded String


byKeyOf : List Terrain -> Dict Char Terrain
byKeyOf list =
    list |> List.map (\t -> ( t.key, t )) |> Dict.fromList


firstKey : List Terrain -> Char
firstKey list =
    List.head list |> Maybe.map .key |> Maybe.withDefault empty


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotPalette (Ok terrains) ->
            let
                byKey =
                    byKeyOf terrains

                active =
                    if Dict.member model.active byKey then
                        model.active

                    else
                        firstKey terrains
            in
            ( { model | palette = terrains, byKey = byKey, active = active, status = "ready" }, Cmd.none )

        GotPalette (Err _) ->
            ( { model | status = "could not load palette.json" }, Cmd.none )

        GotOverlay i (Ok list) ->
            ( { model | overlays = updateOverlay i (\o -> { o | palette = list, byKey = byKeyOf list, active = firstKey list }) model.overlays }, Cmd.none )

        GotOverlay i (Err _) ->
            ( { model | status = "could not load " ++ (getOverlay i model.overlays |> Maybe.map .url |> Maybe.withDefault "an overlay") }, Cmd.none )

        SelectTerrain k ->
            ( { model | active = k, layer = TerrainLayer }, Cmd.none )

        SelectOverlay i k ->
            ( { model | overlays = updateOverlay i (\o -> { o | active = k }) model.overlays, layer = OverlayLayer i }, Cmd.none )

        SetLayer layer ->
            ( { model | layer = layer }, Cmd.none )

        ToggleTerrainRotation ->
            ( { model | terrainRotation = not model.terrainRotation }, Cmd.none )

        ToggleOverlayRotation i ->
            ( { model | overlays = updateOverlay i (\o -> { o | rotation = not o.rotation }) model.overlays }, Cmd.none )

        Tick ->
            ( { model | tick = model.tick + 1 }, Cmd.none )

        SelectTool t ->
            ( { model | tool = t }, Cmd.none )

        CellMouseDown x y ->
            case model.tool of
                Eyedropper ->
                    ( eyedrop x y model, Cmd.none )

                Fill ->
                    ( setActiveGrid (floodFill x y (activeKey model) (activeGrid model)) (pushHistory model), Cmd.none )

                Paint ->
                    let
                        painted =
                            setActiveGrid (setCell x y (activeKey model) (activeGrid model)) (pushHistory model)
                    in
                    ( { painted | painting = True }, Cmd.none )

        CellMouseEnter x y ->
            let
                hovered =
                    { model | cursor = Just ( x, y ) }
            in
            if model.painting then
                ( setActiveGrid (setCell x y (activeKey hovered) (activeGrid hovered)) hovered, Cmd.none )

            else
                ( hovered, Cmd.none )

        StopPaint ->
            ( { model | painting = False }, Cmd.none )

        Pan dx dy ->
            ( { model
                | vx = clamp 0 (max 0 (model.map.width - 1)) (model.vx + dx)
                , vy = clamp 0 (max 0 (model.map.height - 1)) (model.vy + dy)
              }
            , Cmd.none
            )

        SetNewW s ->
            ( { model | newW = s }, Cmd.none )

        SetNewH s ->
            ( { model | newH = s }, Cmd.none )

        NewMap ->
            let
                w =
                    String.toInt model.newW |> Maybe.withDefault 64 |> clamp 1 1000

                h =
                    String.toInt model.newH |> Maybe.withDefault 40 |> clamp 1 1000

                pushed =
                    pushHistory model
            in
            ( { pushed
                | map = makeMap w h (grasslandKey model)
                , overlays = List.map (\o -> { o | grid = makeMap w h empty }) model.overlays
                , vx = 0
                , vy = 0
                , status = "new map"
              }
            , Cmd.none
            )

        Undo ->
            case model.history of
                prev :: rest ->
                    ( restore prev { model | history = rest, future = current model :: model.future, status = "undo" }, Cmd.none )

                [] ->
                    ( { model | status = "nothing to undo" }, Cmd.none )

        Redo ->
            case model.future of
                next :: rest ->
                    ( restore next { model | future = rest, history = current model :: model.history, status = "redo" }, Cmd.none )

                [] ->
                    ( { model | status = "nothing to redo" }, Cmd.none )

        SaveMap ->
            ( { model | status = "saved " ++ model.name ++ ".json" }
            , Download.string (model.name ++ ".json") "application/json" (encodeMap model)
            )

        LoadRequested ->
            ( model, Select.file [ "application/json" ] FileSelected )

        FileSelected file ->
            ( { model | name = dropExtension (File.name file) }, Task.perform FileLoaded (File.toString file) )

        FileLoaded contents ->
            case D.decodeString mapDecoder contents of
                Ok loaded ->
                    ( { model
                        | name = loaded.name
                        , map = loaded.terrain
                        , overlays = List.map2 (\o g -> { o | grid = g }) model.overlays loaded.overlayGrids
                        , history = []
                        , future = []
                        , vx = 0
                        , vy = 0
                        , status = "loaded " ++ loaded.name
                      }
                    , Cmd.none
                    )

                Err _ ->
                    ( { model | status = "could not parse that map file" }, Cmd.none )


current : Model -> Snapshot
current model =
    { terrain = model.map, overlays = List.map .grid model.overlays }


restore : Snapshot -> Model -> Model
restore snap model =
    { model | map = snap.terrain, overlays = List.map2 (\o g -> { o | grid = g }) model.overlays snap.overlays }


pushHistory : Model -> Model
pushHistory model =
    { model | history = current model :: model.history, future = [], status = "edited" }


activeGrid : Model -> MapData
activeGrid model =
    case model.layer of
        TerrainLayer ->
            model.map

        OverlayLayer i ->
            getOverlay i model.overlays |> Maybe.map .grid |> Maybe.withDefault model.map


setActiveGrid : MapData -> Model -> Model
setActiveGrid grid model =
    case model.layer of
        TerrainLayer ->
            { model | map = grid }

        OverlayLayer i ->
            { model | overlays = updateOverlay i (\o -> { o | grid = grid }) model.overlays }


activeKey : Model -> Char
activeKey model =
    case model.layer of
        TerrainLayer ->
            model.active

        OverlayLayer i ->
            getOverlay i model.overlays |> Maybe.map .active |> Maybe.withDefault empty


eyedrop : Int -> Int -> Model -> Model
eyedrop x y model =
    let
        picked =
            getCell x y (activeGrid model) |> Maybe.withDefault (activeKey model)
    in
    case model.layer of
        TerrainLayer ->
            { model | active = picked }

        OverlayLayer i ->
            { model | overlays = updateOverlay i (\o -> { o | active = picked }) model.overlays }


dropExtension : String -> String
dropExtension s =
    case String.split "." s of
        [ single ] ->
            single

        parts ->
            parts |> List.take (List.length parts - 1) |> String.join "."



-- ENCODE / DECODE


encodeMap : Model -> String
encodeMap model =
    E.encode 2 <|
        E.object
            ([ ( "name", E.string model.name )
             , ( "width", E.int model.map.width )
             , ( "height", E.int model.map.height )
             , ( "rows", E.list E.string (rowsToStrings model.map) )
             ]
                ++ List.map (\o -> ( o.field, E.list E.string (rowsToStrings o.grid) )) model.overlays
            )


type alias LoadedMap =
    { name : String, terrain : MapData, overlayGrids : List MapData }


{-| Decode the base fields, then one grid per overlay field (in `overlayTitles`
order), so any number of layers decodes without an arity ceiling.
-}
mapDecoder : D.Decoder LoadedMap
mapDecoder =
    D.map4 (\name w h rows -> { name = name, w = w, h = h, rows = rows })
        (D.field "name" D.string)
        (D.field "width" D.int)
        (D.field "height" D.int)
        (D.field "rows" (D.list D.string))
        |> D.andThen
            (\base ->
                overlayTitles
                    |> List.map (\field -> D.map (overlayGrid base.w base.h) (D.maybe (D.field field (D.list D.string))))
                    |> combine
                    |> D.map
                        (\grids ->
                            { name = base.name
                            , terrain = { width = base.w, height = base.h, rows = rowsFromStrings base.rows }
                            , overlayGrids = grids
                            }
                        )
            )


combine : List (D.Decoder a) -> D.Decoder (List a)
combine =
    List.foldr (D.map2 (::)) (D.succeed [])


overlayGrid : Int -> Int -> Maybe (List String) -> MapData
overlayGrid w h rows =
    case rows of
        Just rr ->
            { width = w, height = h, rows = rowsFromStrings rr }

        Nothing ->
            makeMap w h empty



-- VIEW


view : Model -> Html Msg
view model =
    div [ A.style "font-family" "monospace", A.style "background" "#0f1115", A.style "color" "#ddd", A.style "min-height" "100vh", A.style "padding" "8px", A.style "display" "flex", A.style "gap" "16px", A.style "align-items" "flex-start" ]
        [ div [ A.style "flex" "1", A.style "min-width" "0" ]
            [ div [ A.style "display" "flex", A.style "gap" "16px", A.style "flex-wrap" "wrap", A.style "align-items" "flex-start" ]
                [ layerView model
                , paletteView model
                , toolsView model
                ]
            , gridView model
            , statusView model
            ]
        , editorsColumn model
        ]


editorsColumn : Model -> Html Msg
editorsColumn model =
    div [ A.style "display" "flex", A.style "flex-direction" "column", A.style "gap" "4px", A.style "min-width" "150px" ]
        (div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "editors" ]
            :: editorLink "/terrain.html" "edit terrain ↗"
            :: List.map (\o -> editorLink o.editorHref ("edit " ++ o.title ++ " ↗")) model.overlays
        )


layerView : Model -> Html Msg
layerView model =
    div []
        [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "layer (↻ = visibility rotation)" ]
        , div [ A.style "display" "flex", A.style "flex-direction" "column", A.style "gap" "4px" ]
            (layerRow model TerrainLayer "terrain" model.terrainRotation ToggleTerrainRotation
                :: List.indexedMap (\i o -> layerRow model (OverlayLayer i) o.title o.rotation (ToggleOverlayRotation i)) model.overlays
            )
        ]


layerRow : Model -> Layer -> String -> Bool -> Msg -> Html Msg
layerRow model layer label rotationOn toggleMsg =
    div [ A.style "display" "flex", A.style "gap" "4px" ]
        [ layerButton model layer label
        , rotationToggle rotationOn toggleMsg
        ]


layerButton : Model -> Layer -> String -> Html Msg
layerButton model layer label =
    button
        [ onClick (SetLayer layer)
        , A.style "background" (highlightIf (model.layer == layer))
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "cursor" "pointer"
        , A.style "flex" "1"
        , A.style "text-align" "left"
        ]
        [ text label ]


rotationToggle : Bool -> Msg -> Html Msg
rotationToggle on msg =
    button
        [ onClick msg
        , A.title
            (if on then
                "in visibility rotation — click to exclude"

             else
                "excluded from visibility rotation — click to include"
            )
        , A.style "background" (highlightIf on)
        , A.style "color"
            (if on then
                "#8bc34a"

             else
                "#777"
            )
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "cursor" "pointer"
        ]
        [ text "↻" ]


paletteView : Model -> Html Msg
paletteView model =
    case model.layer of
        TerrainLayer ->
            paletteSection "terrain" (List.map (paletteButton SelectTerrain model.active) model.palette)

        OverlayLayer i ->
            case getOverlay i model.overlays of
                Just o ->
                    paletteSection o.title (noneButton (SelectOverlay i) o.active :: List.map (paletteButton (SelectOverlay i) o.active) o.palette)

                Nothing ->
                    text ""


paletteSection : String -> List (Html Msg) -> Html Msg
paletteSection label buttons =
    div []
        [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text label ]
        , div [ A.style "display" "flex", A.style "flex-wrap" "wrap", A.style "max-width" "360px", A.style "gap" "4px" ] buttons
        ]


paletteButton : (Char -> Msg) -> Char -> Terrain -> Html Msg
paletteButton toMsg activeK t =
    button
        [ onClick (toMsg t.key)
        , A.style "background" (highlightIf (t.key == activeK))
        , A.style "color" (cssColor t.color)
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 6px"
        , A.style "cursor" "pointer"
        , A.style "font-family" "monospace"
        ]
        [ text (t.glyph ++ " " ++ t.id) ]


noneButton : (Char -> Msg) -> Char -> Html Msg
noneButton toMsg activeK =
    button
        [ onClick (toMsg empty)
        , A.style "background" (highlightIf (activeK == empty))
        , A.style "color" "#aaa"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 6px"
        , A.style "cursor" "pointer"
        ]
        [ text "· none (erase)" ]


toolsView : Model -> Html Msg
toolsView model =
    div []
        [ div [ A.style "opacity" "0.7", A.style "margin-bottom" "4px" ] [ text "tools" ]
        , div [ A.style "display" "flex", A.style "gap" "4px", A.style "flex-wrap" "wrap" ]
            [ toolButton model Paint "paint"
            , toolButton model Fill "fill"
            , toolButton model Eyedropper "pick"
            , plainButton Undo "undo"
            , plainButton Redo "redo"
            , plainButton SaveMap "save"
            , plainButton LoadRequested "load"
            ]
        , div [ A.style "margin-top" "8px", A.style "display" "flex", A.style "gap" "4px", A.style "align-items" "center" ]
            [ text "new "
            , sizeInput model.newW SetNewW
            , text "×"
            , sizeInput model.newH SetNewH
            , plainButton NewMap "create"
            ]
        , div [ A.style "margin-top" "8px", A.style "display" "flex", A.style "gap" "4px" ]
            [ plainButton (Pan -16 0) "◀"
            , plainButton (Pan 16 0) "▶"
            , plainButton (Pan 0 -8) "▲"
            , plainButton (Pan 0 8) "▼"
            ]
        ]


toolButton : Model -> Tool -> String -> Html Msg
toolButton model t label =
    button
        [ onClick (SelectTool t)
        , A.style "background" (highlightIf (t == model.tool))
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "cursor" "pointer"
        ]
        [ text label ]


plainButton : Msg -> String -> Html Msg
plainButton msg label =
    button
        [ onClick msg
        , A.style "background" "#1a1d24"
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "cursor" "pointer"
        ]
        [ text label ]


editorLink : String -> String -> Html Msg
editorLink href label =
    a
        [ A.href href
        , A.target "_blank"
        , A.style "background" "#1a1d24"
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        , A.style "padding" "4px 8px"
        , A.style "text-decoration" "none"
        ]
        [ text label ]


highlightIf : Bool -> String
highlightIf on =
    if on then
        "#2b3550"

    else
        "#1a1d24"


sizeInput : String -> (String -> Msg) -> Html Msg
sizeInput val toMsg =
    input
        [ A.value val
        , onInput toMsg
        , A.style "width" "48px"
        , A.style "background" "#1a1d24"
        , A.style "color" "#ddd"
        , A.style "border" "1px solid #333"
        ]
        []


gridView : Model -> Html Msg
gridView model =
    let
        rows =
            List.range model.vy (min (model.vy + viewportH - 1) (model.map.height - 1))
    in
    div
        [ A.style "margin-top" "10px"
        , A.style "line-height" "1.05"
        , A.style "font-size" "16px"
        , A.style "background" "#000"
        , A.style "padding" "6px"
        , A.style "display" "inline-block"
        , A.style "border" "1px solid #222"
        , A.style "user-select" "none"
        ]
        (List.map (rowView model) rows)


rowView : Model -> Int -> Html Msg
rowView model y =
    let
        cols =
            List.range model.vx (min (model.vx + viewportW - 1) (model.map.width - 1))
    in
    div [ A.style "white-space" "pre" ] (List.map (\x -> cellView model x y) cols)


cellView : Model -> Int -> Int -> Html Msg
cellView model x y =
    let
        ( glyph, color ) =
            displayCell model x y

        highlight =
            model.cursor == Just ( x, y )
    in
    span
        [ onMouseEnter (CellMouseEnter x y)
        , onMouseDown (CellMouseDown x y)
        , A.style "color" color
        , A.style "display" "inline-block"
        , A.style "width" "1ch"
        , A.style "background"
            (if highlight then
                "#444"

             else
                "transparent"
            )
        ]
        [ text glyph ]


{-| The glyph drawn at a tile. Visibility rotation cycles, one symbol per
second, through every rotation-enabled layer with something on this tile, so a
tile carrying several items reveals each in turn. When the rotation set is empty
(all contributing layers are excluded), fall back to the topmost occupied layer
so a tile is never blank.
-}
displayCell : Model -> Int -> Int -> ( String, String )
displayCell model x y =
    case rotationStack model x y of
        [] ->
            topCell model x y

        stack ->
            List.drop (modBy (List.length stack) model.tick) stack
                |> List.head
                |> Maybe.withDefault (topCell model x y)


{-| The rotation-enabled symbols present at a tile, ordered top to bottom so the
first frame matches the static top-of-stack view. Terrain is always present, so
it contributes whenever its rotation is enabled.
-}
rotationStack : Model -> Int -> Int -> List ( String, String )
rotationStack model x y =
    (List.reverse model.overlays
        |> List.filterMap
            (\o ->
                if o.rotation then
                    overlayAt x y o.grid o.byKey

                else
                    Nothing
            )
    )
        ++ (if model.terrainRotation then
                [ terrainCell model x y ]

            else
                []
           )


terrainCell : Model -> Int -> Int -> ( String, String )
terrainCell model x y =
    let
        terrainCh =
            getCell x y model.map |> Maybe.withDefault ' '
    in
    case Dict.get terrainCh model.byKey of
        Just t ->
            ( t.glyph, cssColor t.color )

        Nothing ->
            ( String.fromChar terrainCh, "#888" )


{-| The glyph drawn at a tile: the topmost overlay with something there, else
the terrain. Overlays are stored bottom-to-top, so the search runs in reverse.
-}
topCell : Model -> Int -> Int -> ( String, String )
topCell model x y =
    firstJust (List.reverse model.overlays |> List.map (\o -> overlayAt x y o.grid o.byKey))
        |> Maybe.withDefault (terrainCell model x y)


firstJust : List (Maybe a) -> Maybe a
firstJust list =
    case list of
        [] ->
            Nothing

        (Just v) :: _ ->
            Just v

        Nothing :: rest ->
            firstJust rest


overlayAt : Int -> Int -> MapData -> Dict Char Terrain -> Maybe ( String, String )
overlayAt x y grid dict =
    let
        ch =
            getCell x y grid |> Maybe.withDefault empty
    in
    if ch == empty then
        Nothing

    else
        Dict.get ch dict |> Maybe.map (\t -> ( t.glyph, cssColor t.color ))


statusView : Model -> Html Msg
statusView model =
    let
        cursorText =
            case model.cursor of
                Just ( x, y ) ->
                    String.fromInt x ++ "," ++ String.fromInt y

                Nothing ->
                    "—"

        layerText =
            case model.layer of
                TerrainLayer ->
                    "terrain:" ++ nameOf model.active model.byKey

                OverlayLayer i ->
                    case getOverlay i model.overlays of
                        Just o ->
                            o.title ++ ":" ++ overlayName o.active o.byKey

                        Nothing ->
                            "?"
    in
    div [ A.style "margin-top" "8px", A.style "opacity" "0.85" ]
        [ text
            (String.join "  ·  "
                [ model.name ++ " (" ++ String.fromInt model.map.width ++ "×" ++ String.fromInt model.map.height ++ ")"
                , "cursor " ++ cursorText
                , "view " ++ String.fromInt model.vx ++ "," ++ String.fromInt model.vy
                , layerText
                , model.status
                ]
            )
        ]


nameOf : Char -> Dict Char Terrain -> String
nameOf k dict =
    Dict.get k dict |> Maybe.map .id |> Maybe.withDefault (String.fromChar k)


overlayName : Char -> Dict Char Terrain -> String
overlayName k dict =
    if k == empty then
        "none"

    else
        nameOf k dict


cssColor : String -> String
cssColor name =
    case name of
        "black" ->
            "#1b1b1b"

        "red" ->
            "#d35f5f"

        "green" ->
            "#3c9a4e"

        "yellow" ->
            "#c9b458"

        "blue" ->
            "#3a78c2"

        "magenta" ->
            "#b05fb0"

        "cyan" ->
            "#4dd0e1"

        "white" ->
            "#cfcfcf"

        "bright_black" ->
            "#7a7a7a"

        "bright_red" ->
            "#ff6b6b"

        "bright_green" ->
            "#8bc34a"

        "bright_yellow" ->
            "#e6c84f"

        "bright_blue" ->
            "#5b9be0"

        "bright_magenta" ->
            "#e07be0"

        "bright_cyan" ->
            "#7fe7f3"

        "bright_white" ->
            "#ffffff"

        _ ->
            "#aaaaaa"



-- MAIN


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 1000 (always Tick)
        , if model.painting then
            Browser.Events.onMouseUp (D.succeed StopPaint)

          else
            Sub.none
        ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }
