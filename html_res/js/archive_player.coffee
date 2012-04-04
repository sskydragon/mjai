window.console ||= {}
window.console.log ||= ->
window.console.error ||= ->

TSUPAIS = [null, "E", "S", "W", "N", "P", "F", "C"]

TSUPAI_IMAGE_MAP =
  "E": "ji_e"
  "S": "ji_s"
  "W": "ji_w"
  "N": "ji_n"
  "P": "no"
  "F": "ji_h"
  "C": "ji_c"

kyokus = []
currentKyokuId = 0
currentActionId = 0

parsePai = (pai) ->
  if pai.match(/^([1-9])(.)(r)?$/)
    return {
      type: RegExp.$2
      number: parseInt(RegExp.$1)
      red: if RegExp.$3 then true else false
    }
  else
    return {
      type: "t"
      number: TSUPAIS.indexOf(pai)
      red: false
    }

comparePais = (lhs, rhs) ->
  parsedLhs = parsePai(lhs)
  lhsRep = parsedLhs.type + parsedLhs.number + (if parsedLhs.red then "1" else "0")
  parsedRhs = parsePai(rhs)
  rhsRep = parsedRhs.type + parsedRhs.number + (if parsedRhs.red then "1" else "0")
  if lhsRep < rhsRep
    return -1
  else if lhsRep > rhsRep
    return 1
  else
    return 0

sortPais = (pais) ->
  pais.sort(comparePais)

paiToImageUrl = (pai, pose) ->
  if pai
    if pai == "?"
      name = "bk"
    else
      parsedPai = parsePai(pai)
      if parsedPai.type == "t"
        name = TSUPAI_IMAGE_MAP[pai]
      else
        name = "#{parsedPai.type}s#{parsedPai.number}"
    if pose == undefined
      pose = 1
    return window.resourceDir + "/images/p_#{name}_#{pose}.gif"
  else
    return window.resourceDir + "/images/blank.png"

cloneBoard = (board) ->
  newBoard = {}
  for bk, bv of board
    if bk == "players"
      newBoard[bk] = []
      for player in bv
        newPlayer = {}
        for pk, pv of player
          newPlayer[pk] = pv
        newBoard[bk].push(newPlayer)
    else
      newBoard[bk] = bv
  return newBoard

initPlayers = (board) ->
  for player in board.players
    player.tehais = null
    player.furos = []
    player.ho = []
    player.reach = false
    player.reachHoIndex = null

removeRed = (pai) ->
  return null if !pai
  if pai.match(/^(.+)r$/)
    return RegExp.$1
  else
    return pai

loadAction = (action) ->
  
  #console.log(action.type, action)
  if kyokus.length > 0
    kyoku = kyokus[kyokus.length - 1]
    board = cloneBoard(kyoku.actions[kyoku.actions.length - 1].board)
  else
    kyoku = null
    board = null
  if board && ("actor" of action)
    actorPlayer = board.players[action.actor]
  else
    actorPlayer = null
  if board && ("target" of action)
    targetPlayer = board.players[action.target]
  else
    targetPlayer = null
  
  switch action.type
    when "start_game"
      null
    when "end_game"
      null
    when "start_kyoku"
      kyoku =
        actions: []
        doraMarkers: [action.dora_marker]
      kyokus.push(kyoku)
      board =
        players: [{}, {}, {}, {}]
      initPlayers(board)
    when "end_kyoku"
      null
    when "haipai"
      actorPlayer.tehais = action.pais
      sortPais(actorPlayer.tehais)
    when "tsumo"
      actorPlayer.tehais = actorPlayer.tehais.concat([action.pai])
    when "dahai"
      deleteTehai(actorPlayer, action.pai)
      actorPlayer.ho = actorPlayer.ho.concat([action.pai])
    when "reach"
      actorPlayer.reachHoIndex = actorPlayer.ho.length
    when "reach_accepted"
      actorPlayer.reach = true
    when "chi", "pon", "daiminkan"
      targetPlayer.ho = targetPlayer.ho[0...(targetPlayer.ho.length - 1)]
      for pai in action.consumed
        deleteTehai(actorPlayer, pai)
      actorPlayer.furos = actorPlayer.furos.concat([
          type: action.type
          taken: action.pai
          consumed: action.consumed
          target: action.target
      ])
    when "ankan"
      for pai in action.consumed
        deleteTehai(actorPlayer, pai)
      actorPlayer.furos = actorPlayer.furos.concat([
          type: action.type
          consumed: action.consumed
      ])
    when "kakan"
      deleteTehai(actorPlayer, action.pai)
      actorPlayer.furos = actorPlayer.furos.concat([])
      furos = actorPlayer.furos
      for i in [0...furos.length]
        if furos[i].type == "pon" && removeRed(furos[i].taken) == removeRed(action.pai)
          furos[i] =
            type: "kakan"
            taken: action.pai
            consumed: action.consumed
            target: furos[i].target
    when "hora", "ryukyoku"
      null
    when "dora"
      board.doraMarkers = board.doraMarkers.concat([action.dora_marker])
    when "log"
      if kyoku
        kyoku.actions[kyoku.actions.length - 1].log = action.text
    else
      throw "unknown action: #{action.type}"
  
  if kyoku
    for i in [0...4]
      if i != action.actor
        ripai(board.players[i])
    if action.type != "log"
      action.board = board
      #dumpBoard(board)
      kyoku.actions.push(action)

deleteTehai = (player, pai) ->
  player.tehais = player.tehais.concat([])
  idx = player.tehais.lastIndexOf(pai)
  if idx < 0
    idx = player.tehais.lastIndexOf("?")
  throw "pai not in tehai" if idx < 0
  player.tehais[idx] = null

ripai = (player) ->
  if player.tehais
    player.tehais = (pai for pai in player.tehais when pai)
    sortPais(player.tehais)

dumpBoard = (board) ->
  for i in [0...4]
    player = board.players[i]
    if player.tehais
      tehaisStr = player.tehais.join(" ")
      for furo in player.furos
        consumedStr = furo.consumed.join(" ")
        tehaisStr += " [#{furo.taken}/#{consumedStr}]"
      console.log("[#{i}] tehais: #{tehaisStr}")
    if player.ho
      hoStr = player.ho.join(" ")
      console.log("[#{i}] ho: #{hoStr}")

renderPai = (pai, view, pose) ->
  if pose == undefined
    pose = 1
  view.attr("src", paiToImageUrl(pai, pose))
  switch pose
    when 1
      view.addClass("pai")
      view.removeClass("laid-pai")
    when 3
      view.addClass("laid-pai")
      view.removeClass("pai")
    else
      throw("unknown pose")

renderPais = (pais, view, poses) ->
  pais ||= []
  poses ||= []
  view.clear()
  for i in [0...pais.length]
    renderPai(pais[i], view.append(), poses[i])

renderHo = (player, offset, pais, view) ->
  if player.reachHoIndex == null
    reachIndex = null
  else
    reachIndex = player.reachHoIndex - offset
  view.clear()
  for i in [0...pais.length]
    renderPai(pais[i], view.append(), if i == reachIndex then 3 else 1)

renderAction = (action) ->
  #console.log(action.type, action)
  actorStr = if action.actor == undefined then "" else action.actor
  $("#action-label").text("#{action.type} #{actorStr}")
  #dumpBoard(action.board)
  kyoku = getCurrentKyoku()
  for i in [0...4]
    player = action.board.players[i]
    view = Dytem.players.at(i)
    if !player.tehais
      renderPais([], view.tehais)
      view.tsumoPai.hide()
    else if player.tehais.length % 3 == 2
      renderPais(player.tehais[0...(player.tehais.length - 1)], view.tehais)
      view.tsumoPai.show()
      renderPai(player.tehais[player.tehais.length - 1], view.tsumoPai)
    else
      renderPais(player.tehais, view.tehais)
      view.tsumoPai.hide()
    ho = player.ho || []
    renderHo(player, 0, ho[0...6], view.hoRows.at(0).pais)
    renderHo(player, 6, ho[6...12], view.hoRows.at(1).pais)
    renderHo(player, 12, ho[12...], view.hoRows.at(2).pais)
    view.furos.clear()
    if player.furos
      j = player.furos.length - 1
      while j >= 0
        furo = player.furos[j]
        furoView = view.furos.append()
        if furo.type == "ankan"
          pais = ["?"].concat(furo.consumed[0...2]).concat(["?"])
          poses = [1, 1, 1, 1]
        else
          dir = (4 + furo.target - i) % 4
          if furo.type in ["daiminkan", "kakan"]
            laidPos = [null, 3, 1, 0][dir]
          else
            laidPos = [null, 2, 1, 0][dir]
          pais = furo.consumed.concat([])
          poses = [1, 1, 1]
          pais[laidPos...laidPos] = [furo.taken]
          poses[laidPos...laidPos] = [3]
        renderPais(pais, furoView.pais, poses)
        --j
  wanpais = ["?", "?", "?", "?", "?", "?"]
  for i in [0...kyoku.doraMarkers.length]
    wanpais[i + 2] = kyoku.doraMarkers[i]
  renderPais(wanpais, Dytem.wanpais)

getCurrentKyoku = ->
  return kyokus[currentKyokuId]

renderCurrentAction = ->
  renderAction(getCurrentKyoku().actions[currentActionId])

goNext = ->
  return if currentActionId == getCurrentKyoku().actions.length - 1
  ++currentActionId
  $("#action-id-label").val(currentActionId)
  renderCurrentAction()

goBack = ->
  return if currentActionId == 0
  --currentActionId
  $("#action-id-label").val(currentActionId)
  renderCurrentAction()

$ ->
  
  $(window).bind "mousewheel", (e) ->
    e.preventDefault()
    if e.originalEvent.wheelDelta < 0
      goNext()
    else if e.originalEvent.wheelDelta > 0
      goBack()
  
  $("#prev-button").click(goBack)
  $("#next-button").click(goNext)
  
  $("#go-button").click ->
    currentActionId = parseInt($("#action-id-label").val())
    renderCurrentAction()
  
  $("#kyokuSelector").change ->
    currentKyokuId = parseInt($("#kyokuSelector").val())
    currentActionId = 0
    renderCurrentAction()
  
  Dytem.init()
  for i in [0...4]
    playerView = Dytem.players.append()
    playerView.addClass("player-#{i}")
    for j in [0...3]
      playerView.hoRows.append()

  for action in allActions
    loadAction(action)
  for i in [0...kyokus.length]
    $("#kyokuSelector").get(0).options[i] = new Option(i, i)
  console.log("loaded")
  
  #currentActionId = 78
  renderCurrentAction()
