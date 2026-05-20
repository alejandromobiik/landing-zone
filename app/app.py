from flask import Flask, jsonify
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential
import os

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "lz-app"})


@app.route("/")
def index():
    vault_url = os.environ.get("KEYVAULT_URI")
    if not vault_url:
        return jsonify({"error": "KEYVAULT_URI no configurada"}), 500
    try:
        credential = DefaultAzureCredential()
        client = SecretClient(vault_url=vault_url, credential=credential)
        message = client.get_secret("app-message").value
        return jsonify({"message": message})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
