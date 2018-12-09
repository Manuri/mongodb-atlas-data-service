[![Build Status](https://travis-ci.org/ballerina-guides/mongodb-atlas-data-service.svg?branch=master)](https://travis-ci.org/ballerina-guides/mongodb-atlas-data-service)

# MongoDB Atlas data service with Ballerina

Ballerina supports manipulating data of a database quite easily. There are in-built as well as external clients available for interacting with various databases.
> This guide walks you through exposing data from a MongoDB Atlas cloud database hosted on Google Cloud, as a RESTFul service.

The following are the sections available in this guide.

- [What you'll build](#what-youll-build)
- [Prerequisites](#prerequisites)
- [Implementation](#implementation)
- [Testing](#testing)
- [Deployment](#deployment)

## What you'll build

You'll build a RESTful service that provides an API to perform keyword serching on a MongoDB Atlas cloud database cluster.
The service will be depoyed on Google Kubernetes Engine(GKE) of GCP.

## Compatibility

| Ballerina Language Version
| --------------------------
| 0.990.0

## Prerequisites

- [Ballerina Distribution](https://ballerina.io/learn/getting-started/)
- A Text Editor or an IDE
- MongoDB Atlas account - free tier would suffice
- [Google Cloud Platform account](https://cloud.google.com/)

### Optional requirements

- Ballerina IDE plugins ([IntelliJ IDEA](https://plugins.jetbrains.com/plugin/9520-ballerina), [VSCode](https://marketplace.visualstudio.com/items?itemName=WSO2.Ballerina))

## Implementation

### Create the project structure

Ballerina is a complete programming language that can have any custom project structure that you wish. Although the language allows you to have any module structure, use the following module structure for this project to follow this guide.
```
ballerina-gke-deployment
 └── guide
      └── mongodb_atlas_data_service
            └──mongodb-service.bal
```

- Create the above directories in your local machine and also create empty `.bal` file.

- Then open the terminal and navigate to `ballerina-gke-deployment/guide` and run Ballerina project initializing toolkit.
```bash
   $ ballerina init
```

### Set up the MongoDB Atlas cloud database

MongoDB Atlas is a cloud-hosted service for provisioning, running, monitoring, and maintaining MongoDB deployments.
You can easily get an MongoDB Atlas account and a free-tier MongoDB cluster created by following this [tutorial](https://docs.mongodb.com/manual/tutorial/atlas-free-tier-setup/) from
MongoDB documentation.

Once you create the cluster, you can obtain the connection URI of the cluster. There will be two types of connection strings,
Short SRV connection string and Standard connection string. You can use either of them in this guide.

Once you obtain the connection string, import the data in [data.txt](resources/data.txt) in to the cluster using
`mongoimport` utility similar to below. `data.txt` contains JSON documents which contain information on a set of
books and authors of them. This will create a collection named `Books` and insert the documents to that collection.

```bash
mongoimport --uri "mongodb://<user>:<password>@cluster0-shard-00-00-munbd.gcp.mongodb.net:27017,cluster0-shard-00-01-munbd.gcp.mongodb.net:27017,cluster0-shard-00-02-munbd.gcp.mongodb.net:27017/BallerinaDemoDB?ssl=true&replicaSet=Cluster0-shard-0&authSource=admin" --collection Books --file data.json
```

Since we are creating a service that performs a keyword search, we need to create an index for the `Books` collection.
You can do that by connecting the cluster through mongo shell similar to below,

```bash
mongo "mongodb://cluster0-shard-00-00-munbd.gcp.mongodb.net:27017,cluster0-shard-00-01-munbd.gcp.mongodb.net:27017,cluster0-shard-00-02-munbd.gcp.mongodb.net:27017/test?replicaSet=Cluster0-shard-0" --ssl --authenticationDatabase admin --username <username> --password <password>
```

and running the following command. This allows text search over the name and author fields of the `Books` collection.

```bash
MongoDB Enterprise Cluster0-shard-0:PRIMARY> db.Books.createIndex( { name: "text", author: "text" } );
```
## Developing the Ballerina data service

Now we are implemeting the Ballerina HTTP service that exposes the MongoDB database we just created and provides an API to perform search based on keywords.


```ballerina
import ballerina/http;
import ballerina/log;
import ballerinax/kubernetes;
import wso2/mongodb;

// The configuration fields can be obtained from the MongoDB Atlas URI components
mongodb:Client conn = new({
    host: "cluster0-shard-00-00-munbd.gcp.mongodb.net:27017,cluster0-shard-00-01-munbd.gcp.mongodb.net:27017,cluster0-shard-00-02-munbd.gcp.mongodb.net:27017",
    dbName: "BallerinaDemoDB",
    username: "<db_username>",
    password: "<db_password>",
    options: { authSource: "admin", sslEnabled: true, retryWrites: true, replicaSet: "Cluster0-shard-0" }
});

// It is possible to use the direct connection string in the client configuration, as well
//mongodb:Client conn = new({
//    dbName: "BallerinaDemoDB",
//    options : { url: "mongodb://<db_username>:<db_password>@cluster0-shard-00-00-munbd.gcp.mongodb.net:27017,cluster0-shard-00-01-munbd.gcp.mongodb.net:27017,cluster0-shard-00-02-munbd.gcp.mongodb.net:27017/BallerinaDemoDB?ssl=true&replicaSet=Cluster0-shard-0&authSource=admin&retryWrites=true"}
//});

// Also, the short SRV connection string can be used if the driver version is compatible with it
//mongodb:Client conn = new({
//    dbName: "BallerinaDemoDB",
//    options : { url: "mongodb+srv://testuser:test@cluster0-munbd.gcp.mongodb.net/test?retryWrites=true"}
//});

@kubernetes:Service {
    name:"search-service",
    serviceType:"LoadBalancer",
    port:80
}
listener http:Listener httpListener = new(9090);

@kubernetes:Deployment {
    enableLiveness:true,
    image:"<user>/ballerina_mongodbaltas_service:latest",
    push:true,
    username:"<user>",
    password:"<password>",
    baseImage: "mongodb-ballerina:1.0",
    imagePullPolicy: "Always"
}

// By default, Ballerina exposes a service via HTTP/1.1.
service searchService on httpListener {

    @http:ResourceConfig {
        path:"/search/{keyword}"
    }
    resource function search(http:Caller caller, http:Request req, string keyword) {
        http:Response res = new;

        json searchQuery = { "$text": { "$search": keyword } };

        var jsonRet = conn->find("Books", searchQuery);
        if (jsonRet is json) {
            json[] dataArray = <json[]>jsonRet;
            if (dataArray.length() == 0) {
                res.setPayload({ "Status": "No data found for the keyword: `" + untaint keyword + "`"});
            } else {
                res.setPayload({ "Status": "Data found", "Results": jsonRet });
            }
        } else {
            log:printError("Error", err = jsonRet);
            res.statusCode = 500;
            res.setPayload({ "Status": "Error occured during the search" });
        }

        // Send the response back to the caller.
        var result = caller->respond(res);
        if (result is error) {
            log:printError("Error sending response", err = result);
        }
    }
}
```

We will be building a Docker image here and publishing it to Docker Hub. This is required, since we cannot simply have the Docker image in the local registry, and run the Kubernetes applicates in GKE, where it needs to have access to the Docker image in a globally accessible location. For this, an image name should be given in the format $username/$image_name in the "image" property, and "username" and "password" properties needs to contain the Docker Hub account username and password respectively. The property "push" is set to "true" to signal the build process to push the build Docker image to Docker Hub.

You can build the Ballerina service using `$ ballerina build hello_world_service.bal`. You should be able to see the following output.

```bash
ballerina build mongodb_atlas_data_service
Compiling source
    manurip/mongodb_atlas_data_service:0.0.1

Running tests
    manurip/mongodb_atlas_data_service:0.0.1
        No tests found

Generating executable
    ./target/mongodb_atlas_data_service.balx
        @kubernetes:Service                      - complete 1/1
        @kubernetes:Deployment                   - complete 1/1
        @kubernetes:Docker                       - complete 3/3
        @kubernetes:Helm                         - complete 1/1

        Run the following command to deploy the Kubernetes artifacts:
        kubectl apply -f /home/manurip/Documents/Work/Repositories/mongodb-atlas-data-service/guide/target/kubernetes/mongodb_atlas_data_service

        Run the following command to install the application using Helm:
        helm install --name mongodb-atlas-data-service-deployment /home/manurip/Documents/Work/Repositories/mongodb-atlas-data-service/guide/target/kubernetes/mongodb_atlas_data_service/mongodb-atlas-data-service-deployment
```

After the build is complete, the Docker image is created and pushed to Docker Hub. The Kubernetes deployment artifacts are generated as well.

## Deployment

- Configuring GKE environment

Before deploying the service on GKE, you will need to setup the GKE environment to create the Kubernetes cluster and deploy an application.

Let's start by installing the Google Cloud SDK in our local machine. Please refer to [Google Cloud SDK Installation](https://cloud.google.com/sdk/install) in finding the steps for the installation.

Next step is gcloud configuration and creating a Google Cloud Platform project.
You can begin with `gcloud init` command. Detailed information on initialization and creating a GCP project can be found on this<TODO: add link!!!> guide.
Create a project named "BallerinaDemo".

With the following command you can list the projects.

```bash
$ gcloud projects list
PROJECT_ID                NAME              PROJECT_NUMBER
ballerinademo-225007      BallerinaDemo     1036334079773
```

- Create the Kubernetes cluster

Next step is creating a kubernetes cluster in the project we just created.
With a command similar to below, you can create a cluster with minimal resources.

```bash
gcloud container clusters create ballerina_demo_cluster --zone us-central1 --machine-type g1-small --disk-size 30GB --max-nodes-per-pool 1
```

With the following command you can verify the cluster is running.

```bash
$ gcloud container clusters list

ballerina-demo-cluster  us-central1  1.9.7-gke.11    35.239.235.173  g1-small      1.9.7-gke.11  3          RUNNING

Also, with `kubectl get nodes` commands you can verify the connection to the cluster. In next steps we'll be using
`kubectl` in order to create our kubernetes deployment.
Please note that when you create a cluster using gcloud container clusters create, an entry is automatically added to the kubeconfig in your environment, and the current context changes to that cluster. Therefore, we don't have to do any manual
configuration to make it possible for `kubectl` to talk to the cluster.

```bash
$ kubectl get nodes
NAME                                                  STATUS    ROLES     AGE       VERSION
gke-ballerina-demo-clust-default-pool-70ca2fd4-jv97   Ready     <none>    4h        v1.9.7-gke.11
gke-ballerina-demo-clust-default-pool-77c556be-x42n   Ready     <none>    4h        v1.9.7-gke.11
gke-ballerina-demo-clust-default-pool-8a9f3889-l6ks   Ready     <none>    4h        v1.9.7-gke.11
```

- Deploying the Ballerina service in GKE

Since the Kubernetes artifacts were automatically built in the earlier Ballerina application build, we simply have to run the following command to deploy the Ballerina service in GKE:

```bash
kubectl apply -f /home/manurip/Documents/Work/Repositories/mongodb-atlas-data-service/guide/target/kubernetes/mongodb_atlas_data_service
service "search-service" created
deployment.extensions "mongodb-atlas-data-service-deployment" created
```

When you list the pods in Kubernetes, it shows that the current application was deployed successfully.

```bash
$ kubectl get pods
NAME                                                     READY     STATUS    RESTARTS   AGE
mongodb-atlas-data-service-deployment-6c696bcf9f-9xgs6   1/1       Running   0          28m
```

After verifying that the pod is alive, we can list the services to see the status of the Kubernetes service created to represent our Ballerina service:

```bash
$ kubectl get svc
NAME             TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
kubernetes       ClusterIP      10.19.240.1    <none>           443/TCP        9h
search-service   LoadBalancer   10.19.252.7    35.239.75.169    80:32014/TCP   29m
```

## Testing

You've just deployed your first Ballerina service in GKE!. You can test out the service using a web browser with the URL [http://$EXTERNAL-IP/searchService/search/$keyword](http://$EXTERNAL-IP/searchService/search/$keyword), or by running the following cURL command:
Here we are searching for results which contain the keyword "Engineering".

```bash
$ curl http://$EXTERNAL-IP/searchService/search/Engineering
{"Status":"Data found", "Results":[{"_id":1, "name":"Engineering Mathematics", "author":"H K Daas"}, {"_id":10, "name":"Higher engineering mathematics", "author":"J. Bird"}]}
```