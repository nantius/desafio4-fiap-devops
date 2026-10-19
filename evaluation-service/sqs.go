package main

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/sqs"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

// Evento que será enviado para a fila
type EvaluationEvent struct {
	UserID    string    `json:"user_id"`
	FlagName  string    `json:"flag_name"`
	Result    bool      `json:"result"`
	Timestamp time.Time `json:"timestamp"`
}

// sqsAttributeCarrier adapts SQS message attributes to the OTel TextMapCarrier
// interface so the active trace context can be injected into the message. The
// consumer (analytics-service) extracts from the same attributes to continue
// the distributed trace across the queue hop.
type sqsAttributeCarrier map[string]*sqs.MessageAttributeValue

func (c sqsAttributeCarrier) Get(key string) string {
	if v, ok := c[key]; ok && v.StringValue != nil {
		return *v.StringValue
	}
	return ""
}

func (c sqsAttributeCarrier) Set(key, value string) {
	c[key] = &sqs.MessageAttributeValue{
		DataType:    aws.String("String"),
		StringValue: aws.String(value),
	}
}

func (c sqsAttributeCarrier) Keys() []string {
	keys := make([]string, 0, len(c))
	for k := range c {
		keys = append(keys, k)
	}
	return keys
}

// sendEvaluationEvent envia um evento para a fila SQS, propagando o contexto de
// trace via message attributes para ligar o span do analytics-service ao trace.
func (a *App) sendEvaluationEvent(ctx context.Context, userID, flagName string, result bool) {
	// Start a producer span for the SQS send so the service map shows
	// evaluation-service -> SQS -> analytics-service.
	tracer := otel.Tracer(serviceName)
	ctx, span := tracer.Start(ctx, "sqs.send evaluation_service_queue",
		trace.WithSpanKind(trace.SpanKindProducer),
		trace.WithAttributes(
			semconv.MessagingSystemKey.String("aws_sqs"),
			semconv.MessagingDestinationName("evaluation_service_queue"),
			attribute.String("flag.name", flagName),
		),
	)
	defer span.End()

	// Se a URL da fila não foi configurada, apenas loga localmente e sai.
	if a.SqsSvc == nil || a.SqsQueueURL == "" {
		log.Printf("[SQS_DISABLED] Evento: User '%s', Flag '%s', Result '%t'", userID, flagName, result)
		return
	}

	event := EvaluationEvent{
		UserID:    userID,
		FlagName:  flagName,
		Result:    result,
		Timestamp: time.Now().UTC(),
	}

	body, err := json.Marshal(event)
	if err != nil {
		log.Printf("Erro ao serializar evento SQS: %v", err)
		span.RecordError(err)
		return
	}

	// Inject the current trace context (traceparent/tracestate) into SQS
	// message attributes so analytics-service can continue the trace.
	attrs := sqsAttributeCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, attrs)

	// Envia a mensagem
	_, err = a.SqsSvc.SendMessageWithContext(ctx, &sqs.SendMessageInput{
		MessageBody:       aws.String(string(body)),
		QueueUrl:          aws.String(a.SqsQueueURL),
		MessageAttributes: attrs,
	})

	if err != nil {
		log.Printf("Erro ao enviar mensagem para SQS: %v", err)
		span.RecordError(err)
	} else {
		log.Printf("Evento de avaliação enviado para SQS (Flag: %s)", flagName)
	}
}
