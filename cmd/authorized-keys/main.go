package main

import (
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"

	"github.com/c9s/ssh-authorizedkey"
	"github.com/linkernetworks/foundation/logger"
	"github.com/linkernetworks/foundation/service/mongo"

	"gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"

	"golang.org/x/crypto/ssh"
)

func fingerprintKeys(keys []PublicKey) map[string]ssh.PublicKey {
	// load the keys with fingerprints
	keyMap := map[string]ssh.PublicKey{}
	for _, key := range keys {
		// Parse the key, other info ignored
		pk, _, _, _, err := ssh.ParseAuthorizedKey([]byte(key.Key))
		if err != nil {
			panic(err)
		}
		// Get the fingerprint
		fp := ssh.FingerprintSHA256(pk)
		keyMap[fp] = pk
	}
	return keyMap
}

type PublicKey struct {
	// The name of the key
	Name string `json:"name"`

	// The base64 encoded public key
	Key string `json:"key"`

	// The fingerprint of the public key
	Fingerprint string `json:"fingerprint"`
}

type User struct {
	ID   bson.ObjectId `bson:"_id" json:"_id"`
	Keys []PublicKey   `bson:"keys" json:"keys"`
}

type MongoConfig struct {
	mongo.MongoConfig
	UserCollection string `json:"userCollection"`
}

type Config struct {
	Mongo  MongoConfig         `json:"mongo"`
	Logger logger.LoggerConfig `json:"logger"`
}

// To get your fingerprint via command-line
//
//	ssh-keygen -lf ~/.ssh/id_rsa.pub
//
// Run this program:
//
//	go run main.go SHA256:xxxxxx
//	go run main.go $(ssh-keygen -lf ~/.ssh/id_rsa.pub | awk '{ print $2 }')
//
func main() {
	var fingerprintInput string
	var configFile string
	var logDir string = ""
	var mongoURL string = ""
	var defaultMongoUserCollection string = "users"

	flag.StringVar(&fingerprintInput, "fingerprint", "", "ssh public key fingerprint")
	flag.StringVar(&configFile, "config", "", "config file")
	flag.StringVar(&mongoURL, "mongo", "", "mongourl")
	flag.StringVar(&logDir, "logDir", "", "log dir")
	flag.Parse()

	// fingerprint is a MUST
	if fingerprintInput == "" && len(flag.Args()) > 0 {
		fingerprintInput = flag.Arg(0)
	}

	if fingerprintInput == "" {
		logger.Fatal("fingerprint is required")
	}

	// config file is a MUST
	if configFile == "" {
		logger.Fatal("-config option is required.")
	}

	configJSON, err := ioutil.ReadFile(configFile)
	if err != nil {
		logger.Fatalf("Failed to read config file: %v", err)
	}

	var config Config
	if err := json.Unmarshal(configJSON, &config); err != nil {
		logger.Fatalf("Failed to parse config JSON: %v", err)
	}

	logger.Debugln("Setting logger config...")
	if logDir != "" {
		config.Logger.Dir = logDir
	}
	logger.Setup(config.Logger)

	if len(mongoURL) > 0 {
		logger.Debugf("Using mongo URL from option: %s", mongoURL)
		config.Mongo.Url = mongoURL
	}

	if config.Mongo.UserCollection == "" {
		config.Mongo.UserCollection = defaultMongoUserCollection
	}

	logger.Debugf("Connecting to mongo: %s", config.Mongo.Url)
	session, err := mgo.Dial(config.Mongo.Url)
	if err != nil {
		logger.Fatal(err)
	}
	logger.Debugf("Mongo connected")

	logger.Infof("Finding user key with fingerprint %s", fingerprintInput)
	var user User
	// session.DB("")
	if err := session.DB(config.Mongo.Database).C(config.Mongo.UserCollection).Find(bson.M{
		"keys.fingerprint": fingerprintInput,
	}).One(&user); err != nil {
		logger.Fatal(err)
	}

	// load the entries
	logger.Infof("Found user keys: %d", len(user.Keys))
	for fp, pk := range fingerprintKeys(user.Keys) {
		logger.Infof("Checking user key: %s", fp)
		if fingerprintInput == fp {
			logger.Infof("Matched user key: %s", fp)
			entry := authorizedkey.AuthorizedKeyEntry{
				KeyType: pk.Type(),
				Key:     base64.StdEncoding.EncodeToString(pk.Marshal()),
				Command: "/git-command " + user.ID.Hex(),
				// Environment:       map[string]string{"foo": "bar"},
				NoAgentForwarding: true,
				NoX11Forwarding:   true,
				NoPty:             true,
				NoPortForwarding:  true,
			}
			fmt.Println(entry)
		}
	}
}
