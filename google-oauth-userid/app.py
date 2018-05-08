from gevent.wsgi import WSGIServer
from flask import Flask, redirect, url_for
from flask_dance.contrib.google import make_google_blueprint, google
from werkzeug.contrib.fixers import ProxyFix
import os


app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app)
app.secret_key = os.urandom(64)
blueprint = make_google_blueprint(
    client_id=os.environ.get('GOOGLE_CLIENT_ID', ''),
    client_secret=os.environ.get('GOOGLE_CLIENT_SECRET', ''),
    scope=['profile']
)
app.register_blueprint(blueprint, url_prefix='/login')


@app.route('/')
def index():
    if not google.authorized:
        return redirect(url_for('google.login'))
    resp = google.get('/oauth2/v2/userinfo')
    assert resp.ok, resp.text
    return '<h2>Your Google OAuth ID is: {}</h2>'.format(resp.json()["id"])


if __name__ == "__main__":
    http_server = WSGIServer(('0.0.0.0', 8080), app)
    print('serving on {}:{}'.format('0.0.0.0', 8080))
    http_server.serve_forever()
