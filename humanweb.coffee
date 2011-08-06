
sys = require 'sys'
xmpp = require 'node-xmpp'
argv = process.argv

if argv.length != 4
	 console.error "Usage: <jid> <password>"
	 process.exit 1


client = new xmpp.Client {
  jid: argv[2],
  password: argv[3] }

client.on 'online', () ->
  console.log "Connected to xmpp server"
  e = new xmpp.Element('presence', {})
  e.c('show').t('chat').up().c('status').t('Ask me a question!')
  client.send e

client.on 'stanza', (stanza) ->
  console.log(stanza)
  if stanza.is('message') and (stanza.attrs.type == 'chat')
    stanza.attrs.to = stanza.attrs.from
    delete stanza.attrs.from
    client.send(stanza)
  if stanza.is('iq')
    console.log "Sending pong."
    client.send(new xmpp.Element('iq', { to : stanza.attrs.from, id : 'c2s1', type : 'result' }))
  if stanza.is('presence') and (stanza.attrs.type == 'subscribe')
    e = new xmpp.Element('presence', { to : stanza.attrs.from, type : 'subscribed' })
    client.send(e)

client.on 'error', (e) ->
  console.error('Error: ' + e)