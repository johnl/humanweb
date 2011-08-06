
sys = require 'sys'
xmpp = require 'node-xmpp'
argv = process.argv
http = require 'http'

if argv.length != 5
	 console.error "Usage: <jid> <password> <receiverjid>"
	 process.exit 1

buddies = []

client = new xmpp.Client { jid: argv[2], password: argv[3], resource: 'webserver' }

receiver = argv[4]

client.on 'online', () ->
  console.log "Connected to xmpp server"
  e = new xmpp.Element('presence', {})
  e.c('show').t('chat').up().c('status').t('Ask me a question!')
  client.send e

client.on 'stanza', (stanza) ->
#  console.log(stanza)
  if stanza.is('message') and (stanza.attrs.type == 'chat')
    stanza.attrs.to = stanza.attrs.from
    delete stanza.attrs.from
    client.send(stanza)
  if stanza.is('iq')
    console.log "Sending pong."
    client.send(new xmpp.Element('iq', { to : stanza.attrs.from, id : 'c2s1', type : 'result' }))
  if stanza.is('presence') and (stanza.attrs.type == 'subscribe')
    console.log "Subscribing user " + stanza.attrs.from
    e = new xmpp.Element('presence', { to : stanza.attrs.from, type : 'subscribed' })
    client.send e

client.on 'error', (e) ->
  console.error('Error: ' + e)


server = http.createServer( (req, res) ->
  console.log "Received request"
  res.writeHead 200, {'Content-Type': 'text/plain'}
  res.end 'Hello World\n'
  e = new xmpp.Element 'message', { to: receiver, type: 'chat' }
  e.c('body').t req.url
  client.send e
)

server.listen 5000
