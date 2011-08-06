
sys = require 'sys'
xmpp = require 'node-xmpp'
argv = process.argv
http = require 'http'

getRandomInt = (min, max) ->
  return Math.floor(Math.g() * (max - min + 1)) + min;

if argv.length != 4
	 console.error "Usage: <jid> <password> <receiverjid>"
	 process.exit 1

client = new xmpp.Client { jid: argv[2], password: argv[3]  }

Array.prototype.delete = (e) ->
  return if this.indexOf(e) == -1
  this.splice(this.indexOf(e),1)

Array.prototype.random = () ->
  this[getRandomInt(0,this.length - 1)]

Array.prototype.exists = (e) ->
  return this.indexOf(e) >= 0

class Buddylist
  constructor: () ->
    @buddies = {}
    @online = []
    @idle = []

  setOnline: (jid) ->
    return if jid.match(new RegExp('^' + client.jid.user + '@' + client.jid.domain))
    buddy = @buddies[jid] || {}
    @buddies[jid] = buddy
    buddy.jid = jid
    @online.push jid unless @online.exists jid
    this.setIdle jid
    buddy

  setIdle: (jid) ->
    return jid unless @buddies[jid]
    return jid if @idle.exists jid
    @idle.push(jid)
    jid

  setBusy: (jid) ->
    return jid unless @buddies[jid]
    @idle.delete(jid)
    jid

  setOffline: (jid) ->
    return jid unless @buddies[jid]
    @buddies[jid] = undefined
    @online.delete(jid)
    @idle.delete(jid)
    jid

  assignWork: (url, work, fail) ->
    buddy = this.nextIdleBuddy()
    if (buddy)
      buddy.onWorkFinished = work
      this.setBusy(buddy.jid)
      this.sendMessage(buddy.jid, url)

      # In case the user does not respond
      blist = this
      setTimeout ->
        if buddy.onWorkFinished
          blist.setIdle(buddy.jid)
          blist.sendMessage(buddy.jid, "You timed out! Work faster human!")
          fail(504, "The server did not receive a timely response from the upstream human.\n")
      , 90000
    else
      fail(503, "No human available to service your request.\n")

  nextIdleBuddy: () ->
    @buddies[@idle[0]]

  sendMessage: (receiver, message) ->
    console.log "Sending " + message + " to: " + receiver
    e = new xmpp.Element 'message', { to: receiver, type: 'chat' }
    e.c('body').t message
    client.send e

client.buddylist = new Buddylist

client.iq = (query, to = undefined, type = 'get') ->
  attrs = { type: type }
  attrs.to = to if to
  client.send(new xmpp.Element('iq', attrs).cnode(query).tree());

client.getRoster = () ->
  client.iq new xmpp.Element('query', { xmlns: 'jabber:iq:roster' })

client.syncSubscription = (q) ->
  if q.jid
    jid = q.jid
    subscription = q.subscription
  else
    console.error 'HOLI SHITBURGERS'
  switch subscription
    when 'from'
      console.log 'Subscribing to ' + jid
      client.send new xmpp.Element('presence', { to: jid, type: 'subscribe' })
    when 'both'
      console.log 'Already subscribed to ' + jid
    when 'to'
      console.log 'Unsubscribing from ' + jid
      client.send new xmpp.Element('presence', { to: jid, type: 'unsubscribe' })

client.on 'online', () ->
  console.log "Connected to xmpp server"
  e = new xmpp.Element('presence', {})
  e.c('show').t('chat').up().c('status').t('Ask me a question!')
  client.send e
  client.getRoster()

client.on 'stanza', (stanza) ->
  if stanza.is('message') and (stanza.attrs.type == 'chat')
    buddy = client.buddylist.buddies[stanza.attrs.from]
    if buddy == undefined
      console.error 'Received message from unknown buddy ' + stanza.attrs.from
      return

    if buddy.onWorkFinished
      buddy.onWorkFinished(stanza.children[0].children.join(''))
    else
      client.buddylist.sendMessage(buddy.jid, 'No web client currently waiting for message')
    client.buddylist.setIdle(buddy.jid)
  if stanza.is('iq')
    # roster response
    if stanza.attrs.type == 'result' and stanza.children[0].attrs.xmlns == 'jabber:iq:roster'
      console.log 'Received jabber:iq:roster'
      roster = stanza.children[0]
      roster.children.forEach (e) ->
        client.syncSubscription e.attrs
    console.log "Sending pong."
    client.send(new xmpp.Element('iq', { to : stanza.attrs.from, id : 'c2s1', type : 'result' }))
  if stanza.is('presence')
    switch stanza.attrs.type
      when 'subscribe'
        console.log "Subscribing user " + stanza.attrs.from
        e = new xmpp.Element('presence', { to : stanza.attrs.from, type : 'subscribed' })
        client.send e
        client.getRoster()
      when 'unsubscribe'
        console.log "Unsubscribe from " + stanza.attrs.from
        client.getRoster()
      when 'unavailable'
        console.log "Now unavailable: " + stanza.attrs.from
        client.buddylist.setOffline stanza.attrs.from
      else
        console.log "Probably available: " + stanza.attrs.from
        client.buddylist.setOnline stanza.attrs.from

client.on 'error', (e) ->
  console.error('Error: ' + e)

server = http.createServer( (req, res) ->
  if req.url == "/"
    res.writeHead 200, {'Content-type': 'text/html'}
    res.end '<h1>The Human Powered Web Server</h1><p>Welcome to the human powered web server, type any URL in for this domain and the result will be fulfilled by a real live human.</p><p>If you would like to join the workforce, add humanweb@jabber.org to your Jabber or Google Talk buddy list.</p>'
    return
  if req.url.match(/favicon.ico/)
    res.writeHead 404, {'Content-type': 'text/plain'}
    res.end 'Favicons are too hard to type by hand\n'
    return
  msg = req.method + ' ' + req.url + "\n"
  console.log req
  msg += 'X-Forwarded-For: ' + req.socket.remoteAddress + "\n"
  msg += 'User Agent: ' + req.headers["user-agent"]
  client.buddylist.assignWork msg, (message) ->
    res.writeHead 200, {'Content-Type': 'text/html'}
    res.end message + '\n'
  , (errorCode, message) ->
    res.writeHead errorCode, {'Content-Type': 'text/plain'}
    res.end message
)

server.listen 5000
