// Command smoke verifies, from inside the compose network, that the three
// services the interview project depends on behave: the rootchain RPC answers
// and mines blocks, Kafka accepts and returns messages in order on a
// single-partition topic, and Redis answers PING.
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/segmentio/kafka-go"
)

type result struct {
	name string
	ok   bool
	info string
}

func main() {
	rpcURL := env("RPC_URL", "http://anvil:8545")
	broker := env("KAFKA_BROKER", "kafka:9092")
	redisAddr := env("REDIS_ADDR", "redis:6379")

	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	results := []result{
		checkRPC(ctx, rpcURL),
		checkRedis(redisAddr),
		checkKafka(ctx, broker),
	}

	failed := 0
	for _, r := range results {
		mark := "PASS"
		if !r.ok {
			mark = "FAIL"
			failed++
		}
		fmt.Printf("  %s  %-22s %s\n", mark, r.name, r.info)
	}
	if failed > 0 {
		fmt.Printf("in-network checks: %d failed\n", failed)
		os.Exit(1)
	}
	fmt.Println("in-network checks: all passed")
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

// checkRPC calls eth_chainId, then eth_blockNumber twice to prove the chain
// is mining on its own (the project's anvil runs with a 1 second block time).
func checkRPC(ctx context.Context, url string) result {
	chainHex, err := rpcCall(ctx, url, "eth_chainId")
	if err != nil {
		return result{"rootchain rpc", false, err.Error()}
	}
	chainID, _ := strconv.ParseUint(strings.TrimPrefix(chainHex, "0x"), 16, 64)
	b1, err := rpcCall(ctx, url, "eth_blockNumber")
	if err != nil {
		return result{"rootchain rpc", false, err.Error()}
	}
	time.Sleep(2500 * time.Millisecond)
	b2, err := rpcCall(ctx, url, "eth_blockNumber")
	if err != nil {
		return result{"rootchain rpc", false, err.Error()}
	}
	n1, _ := strconv.ParseUint(strings.TrimPrefix(b1, "0x"), 16, 64)
	n2, _ := strconv.ParseUint(strings.TrimPrefix(b2, "0x"), 16, 64)
	if n2 <= n1 {
		return result{"rootchain rpc", false, fmt.Sprintf("chain %d answered but blocks are not advancing (%d -> %d)", chainID, n1, n2)}
	}
	return result{"rootchain rpc", true, fmt.Sprintf("chain %d, blocks advancing (%d -> %d in 2.5s)", chainID, n1, n2)}
}

func rpcCall(ctx context.Context, url, method string) (string, error) {
	body, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": 1, "method": method, "params": []any{}})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
	if err != nil {
		return "", fmt.Errorf("%s: %w", method, err)
	}
	defer func() { _ = resp.Body.Close() }()
	var out struct {
		Result string `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", fmt.Errorf("%s: bad response: %w", method, err)
	}
	if out.Error != nil {
		return "", fmt.Errorf("%s: %s", method, out.Error.Message)
	}
	return out.Result, nil
}

// checkRedis speaks RESP directly so this program needs no Redis client.
func checkRedis(addr string) result {
	conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		return result{"redis", false, err.Error()}
	}
	defer func() { _ = conn.Close() }()
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Write([]byte("*1\r\n$4\r\nPING\r\n")); err != nil {
		return result{"redis", false, err.Error()}
	}
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		return result{"redis", false, err.Error()}
	}
	if strings.TrimSpace(line) != "+PONG" {
		return result{"redis", false, fmt.Sprintf("unexpected reply %q", strings.TrimSpace(line))}
	}
	return result{"redis", true, "PING -> PONG"}
}

// checkKafka creates a single-partition topic, produces three keyed messages,
// and reads them back in order, which is exactly what the project relies on.
func checkKafka(ctx context.Context, broker string) result {
	const topic = "smoke"
	conn, err := kafka.DialContext(ctx, "tcp", broker)
	if err != nil {
		return result{"kafka", false, "dial: " + err.Error()}
	}
	defer func() { _ = conn.Close() }()
	ctrl, err := conn.Controller()
	if err != nil {
		return result{"kafka", false, "controller: " + err.Error()}
	}
	cc, err := kafka.DialContext(ctx, "tcp", net.JoinHostPort(ctrl.Host, strconv.Itoa(ctrl.Port)))
	if err != nil {
		return result{"kafka", false, "dial controller: " + err.Error()}
	}
	defer func() { _ = cc.Close() }()
	_ = cc.CreateTopics(kafka.TopicConfig{Topic: topic, NumPartitions: 1, ReplicationFactor: 1})
	var parts []kafka.Partition
	for i := 0; i < 40; i++ {
		parts, err = cc.ReadPartitions(topic)
		if err == nil && len(parts) > 0 {
			break
		}
		time.Sleep(250 * time.Millisecond)
	}
	if len(parts) != 1 {
		return result{"kafka", false, fmt.Sprintf("topic %q has %d partitions, want 1", topic, len(parts))}
	}

	w := &kafka.Writer{Addr: kafka.TCP(broker), Topic: topic, RequiredAcks: kafka.RequireAll, BatchSize: 3, BatchTimeout: 10 * time.Millisecond}
	stamp := strconv.FormatInt(time.Now().UnixNano(), 10)
	msgs := make([]kafka.Message, 3)
	for i := range msgs {
		msgs[i] = kafka.Message{Key: []byte(strconv.Itoa(i)), Value: []byte(stamp + "-" + strconv.Itoa(i))}
	}
	if err := w.WriteMessages(ctx, msgs...); err != nil {
		_ = w.Close()
		return result{"kafka", false, "produce: " + err.Error()}
	}
	_ = w.Close()

	r := kafka.NewReader(kafka.ReaderConfig{Brokers: []string{broker}, Topic: topic, Partition: 0, StartOffset: kafka.FirstOffset, MinBytes: 1, MaxBytes: 1e6, MaxWait: 200 * time.Millisecond})
	defer func() { _ = r.Close() }()
	got := 0
	rctx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	for got < 3 {
		m, err := r.ReadMessage(rctx)
		if err != nil {
			return result{"kafka", false, fmt.Sprintf("consume: %v (got %d of 3)", err, got)}
		}
		if !strings.HasPrefix(string(m.Value), stamp) {
			continue // a previous run's message
		}
		if string(m.Key) != strconv.Itoa(got) {
			return result{"kafka", false, fmt.Sprintf("out of order: got key %q, want %d", m.Key, got)}
		}
		got++
	}
	return result{"kafka", true, "single-partition topic, 3 messages produced and consumed in order"}
}
