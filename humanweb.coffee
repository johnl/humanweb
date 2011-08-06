
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
  e.c('show').t('chat').up().c('status').t('Accepting requests')
  client.send e

client.on 'stanza', (stanza) ->
  console.log(stanza)
  if stanza.is('message') and (stanza.attrs.type == 'chat')
    stanza.attrs.to = stanza.attrs.from
    delete stanza.attrs.from
    client.send(stanza)

client.on 'error', (e) ->
  console.error('Error: ' + e)