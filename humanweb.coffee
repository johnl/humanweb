
sys = require 'sys'
xmpp = require 'node-xmpp'
argv = process.argv
http = require 'http'

getRandomInt = (min, max) ->
  return Math.floor(Math.random() * (max - min + 1)) + min;

if argv.length != 4
	 console.error "Usage: <jid> <password> <receiverjid>"
	 process.exit 1

client = new xmpp.Client { jid: argv[2], password: argv[3]  }

Array.prototype.delete = (e) ->
  return if this.indexOf(e) == -1
  this.splice(this.indexOf(e),1)

Array.prototype.random = () ->
  this[getRandomInt(0,this.length - 1)]

class Buddylist
  constructor: () ->
    @buddies = {}
    @online = []
    @busy = []

  setOnline: (jid) ->
    buddy = @buddies[jid] || {}
    buddy.jid = jid
    @online.push(jid) if @online.indexOf(jid) == -1
    console.log @online.length + " buddies online"
    buddy

  setOffline: (jid) ->
    @buddies[jid] = undefined
    @online.delete(jid)
    @busy.delete(jid)
    jid

  randomBuddy: () ->
    @online.random()

client.buddylist = new Buddylist
console.log client.buddylist

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
    stanza.attrs.to = stanza.attrs.from
    delete stanza.attrs.from
    client.send(stanza)
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
  console.log "Received request"
  res.writeHead 200, {'Content-Type': 'text/plain'}
  res.end 'Hello World\n'
  receiver = client.buddylist.randomBuddy()
  console.log receiver
  e = new xmpp.Element 'message', { to: receiver, type: 'chat' }
  e.c('body').t req.url
  client.send e
)

server.listen 5000
