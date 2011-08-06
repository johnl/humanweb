
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
    else
      fail()

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

client.on 'online', () ->
  console.log "Connected to xmpp server"
  e = new xmpp.Element('presence', {})
  e.c('show').t('chat').up().c('status').t('Ask me a question!')
  client.send e
  client.getRoster()

client.on 'stanza', (stanza) ->
  if stanza.is('message') and (stanza.attrs.type == 'chat')
    buddy = client.buddylist.buddies[stanza.attrs.from]
    buddy.onWorkFinished(stanza.children[0].children[0])
    client.buddylist.setIdle(buddy.jid)
#    stanza.attrs.to = stanza.attrs.from
#    delete stanza.attrs.from
#    client.send(stanza)
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
      when 'unavailable'
        console.log "Now unavailable: " + stanza.attrs.from
        client.buddylist.setOffline stanza.attrs.from
      else
        console.log "Probably available: " + stanza.attrs.from
        client.buddylist.setOnline stanza.attrs.from

client.on 'error', (e) ->
  console.error('Error: ' + e)

server = http.createServer( (req, res) ->
  if req.url.match(/favicon.ico/)
    res.writeHead 404, {'Content-type': 'text/plain'}
    res.end 'Favicons are too hard to type by hand\n'
    return
  console.log "Received request"
  client.buddylist.assignWork req.url, (message) ->
    res.writeHead 200, {'Content-Type': 'text/plain'}
    res.end message + '\n'
  , () ->
    console.log '503'
    res.writeHead 503, {'Content-Type': 'text/plain'}
    res.end "No human available\n"
)

server.listen 5000
